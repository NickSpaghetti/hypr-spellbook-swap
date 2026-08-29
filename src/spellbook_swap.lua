-- Hyprland glue for the layout-cycling feature. This is the thin I/O layer:
-- it wires the pure logic in core.lua to Hyprland's `hl` API (binds, events,
-- workspace rules, notifications) and to on-disk state. All decisions live in
-- core.
--
-- `Swap` is the module table exported by this file. Prefer loading it by name
-- after `make install`: `local sb = require("hypr-spellbook-swap")`.
local Swap = {}

local function dir_of(path)
    for offset = #path, 1, -1 do
        if path:sub(offset, offset) == "/" then
            return path:sub(1, offset - 1)
        end
    end
    return "."
end

local function script_dir()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return dir_of(source)
end

-- Shallow copy of `base` with `extra`'s keys layered on top. Returns `base`
-- unchanged when `extra` is nil.
local function merged(base, extra)
    if not extra then
        return base
    end
    local out = {}
    for key, value in pairs(base or {}) do
        out[key] = value
    end
    for key, value in pairs(extra) do
        out[key] = value
    end
    return out
end

local REPO = script_dir()
local core = dofile(REPO .. "/core.lua")

local function quoted_path(path)
    return "'" .. path .. "'"
end

local function ensure_dir(path)
    if not core.path_is_safe(path) then
        return false
    end
    local q = quoted_path(path)
    os.execute("mkdir -p -- " .. q .. " && chmod 0700 -- " .. q)
    return true
end

local function chmod_file(path, mode)
    if not core.path_is_safe(path) then
        return
    end
    os.execute("chmod " .. mode .. " -- " .. quoted_path(path))
end

function Swap.setup(opts)
    opts = opts or {}

    -- Hyprland injects `hl` as a global into the config runtime, and required
    -- modules share it. Default to that global; opts.hl overrides it (used by
    -- the tests, and available for advanced setups).
    local hl = opts.hl or hl
    assert(
        hl,
        "hypr-spellbook-swap needs the Hyprland hl API: load it from a Hyprland Lua config, or pass opts.hl"
    )

    -- Warnings go to stderr (Hyprland's log) by default; opts.warn overrides it
    -- (used by the tests).
    local warn = opts.warn
        or function(message)
            io.stderr:write("[hypr-spellbook-swap] " .. message .. "\n")
        end

    local base = opts.layouts or assert(loadfile(opts.layouts_path or (REPO .. "/layouts.lua")))()

    -- Per-field overrides so layout config lives in hyprland.lua via setup opts.
    -- Copy first (merged with {}) so we never mutate the caller's table or the
    -- shared default. This matters because `make install` overwrites the
    -- installed layouts.lua, so editing it is not a durable place for user
    -- config. cycle/default replace; icons/labels merge onto the defaults.
    local config = merged(base, {})
    config.cycle = opts.cycle or config.cycle
    config.default = opts.default or config.default
    config.icons = merged(config.icons, opts.icons)
    config.labels = merged(config.labels, opts.labels)

    local notify = core.resolve_flag(opts.notify, config.notify)
    local sticky = core.resolve_flag(opts.sticky, config.sticky)
    local engine = opts.notification_engine or config.notification_engine or "hyprland"
    local signal = opts.waybar_signal or config.waybar_signal or 8
    local modifier = opts.mod or config.mod or "SUPER"
    local bind_key = opts.key or config.key or "L"

    local state_dir = opts.state_dir or (os.getenv("HOME") .. "/.local/state/hypr-spellbook-swap")
    local state_ok = core.path_is_safe(state_dir)
    if not state_ok then
        warn("state_dir is unsafe (quote, NUL, or newline); persistence disabled")
    end
    local state_file = state_dir .. "/layouts"
    local state_temp_file = state_file .. ".tmp"
    local state = {} -- tagged key ("id:2" / "name:coding") -> layout name

    -- Register custom Lua layouts. Defaults to the bundled providers so the
    -- default cycle's "lua:grid" works out of the box. Pass register = {} to
    -- disable, or your own table to replace.
    local register = opts.register or config.register or dofile(REPO .. "/custom_layouts.lua")
    for name, provider in pairs(register) do
        hl.layout.register(name, provider)
    end

    -- Validate up front (Hyprland silently applies an unknown layout as dwindle,
    -- so catch typos here). Drop unknown entries from the cycle with a warning;
    -- opts.extra_layouts declares extra valid names (e.g. plugin layouts).
    local valid_lua = core.valid_lua_layouts(register, opts.extra_layouts)
    local kept, dropped = core.filter_cycle(config.cycle, valid_lua)
    for _, name in ipairs(dropped) do
        warn("custom layout '" .. name .. "' is not registered; removed from the cycle")
    end
    if core.is_lua_layout(config.default) and not valid_lua[config.default] then
        warn(
            "custom default layout '"
                .. tostring(config.default)
                .. "' is not registered; using 'dwindle'"
        )
        config.default = "dwindle"
    end
    if #kept == 0 then
        warn("no layouts left in the cycle; using the default '" .. config.default .. "'")
        kept = { config.default }
    end
    config.cycle = kept

    -- Persist the effective icons/labels so the out-of-process Waybar emit
    -- (which cannot see these setup opts) renders what you configured, not just
    -- the shipped defaults.
    if state_ok then
        ensure_dir(state_dir)
        local waybar_path = state_dir .. "/waybar.lua"
        local waybar_file = io.open(waybar_path, "w")
        if waybar_file then
            waybar_file:write(core.serialize_config(config))
            waybar_file:close()
            chmod_file(waybar_path, "0600")
        end
    end

    -- Apply using a string we formatted from a live object or a parsed id, never
    -- a raw file field. Numeric IDs only; special workspaces use the object's
    -- config_name because negative IDs are relative selectors in Hyprland.
    local function apply_to_object(workspace, layout)
        if core.is_positive_workspace_id(workspace.id) then
            hl.workspace_rule({ workspace = tostring(workspace.id), layout = layout })
            return
        end
        if workspace.special then
            local selector = workspace.config_name or workspace.name
            if selector then
                hl.workspace_rule({ workspace = selector, layout = layout })
            end
        end
    end

    local function apply_id(id, layout)
        hl.workspace_rule({ workspace = tostring(id), layout = layout })
    end

    local function live_workspaces()
        if hl.get_workspaces then
            return hl.get_workspaces() or {}
        end
        return {}
    end

    local function name_match_count(name)
        local count = 0
        for _, workspace in ipairs(live_workspaces()) do
            if workspace.name == name then
                count = count + 1
            end
        end
        return count
    end

    local function unique_named(name)
        local found = nil
        local count = 0
        for _, workspace in ipairs(live_workspaces()) do
            if workspace.name == name then
                count = count + 1
                found = workspace
            end
        end
        if count > 1 then
            warn("workspace name '" .. name .. "' matches more than one workspace; skipped")
            return nil
        end
        return found
    end

    local function persist()
        if not state_ok then
            return
        end
        ensure_dir(state_dir)
        os.remove(state_temp_file)
        local file = io.open(state_temp_file, "w")
        if file then
            file:write(core.serialize_state(state))
            file:close()
            chmod_file(state_temp_file, "0600")
            os.rename(state_temp_file, state_file)
            chmod_file(state_file, "0600")
        end
    end

    local function save_layout(workspace, layout)
        core.put_saved(state, workspace, layout)
        persist()
    end

    local function read_state(path)
        local file = io.open(path, "r")
        if not file then
            return nil, false
        end
        local parsed, valid = core.parse_state(file:read("*a"))
        file:close()
        return parsed, valid
    end

    local function signal_waybar()
        hl.exec_cmd("pkill -RTMIN+" .. signal .. " waybar")
    end

    local function restore_workspace(workspace)
        if not workspace then
            return
        end
        local saved = core.saved_layout(state, workspace)
        if not saved then
            return
        end
        local name = workspace.name
        if type(name) == "string" and state[core.name_key(name)] == saved then
            if hl.get_workspaces and name_match_count(name) > 1 then
                warn("workspace name '" .. name .. "' matches more than one workspace; skipped")
                return
            end
        end
        if not core.match_key({ saved }, workspace.tiled_layout) then
            apply_to_object(workspace, saved)
        end
    end

    local function restore_active(workspace)
        restore_workspace(workspace or hl.get_active_workspace())
        signal_waybar()
    end

    local function announce(layout)
        local icon, label = core.icon_and_label(config, layout)
        if engine == "sway" then
            hl.exec_cmd(core.notify_send_cmd(label, icon))
        else
            hl.notification.create({ text = label, icon = "ok", timeout = 1500 })
        end
    end

    -- Runtime backstop: layout changes apply asynchronously, so after a short
    -- delay read back the actual layout. If it differs from what we asked for,
    -- Hyprland fell back (the name was not really available) -- warn.
    local function verify_applied(target, requested)
        if not hl.timer then
            save_layout(target, requested)
            return
        end
        local want = core.persist_key(target)
        local timer
        timer = hl.timer(function()
            if timer and timer.set_enabled then
                timer:set_enabled(false)
            end
            local workspace = hl.get_active_workspace()
            if workspace and core.persist_key(workspace) == want then
                if core.match_key({ requested }, workspace.tiled_layout) then
                    save_layout(workspace, requested)
                else
                    warn(
                        "layout '"
                            .. requested
                            .. "' did not apply (now '"
                            .. tostring(workspace.tiled_layout)
                            .. "'); is it available?"
                    )
                end
            end
        end, { timeout = 100, type = "repeat" })
    end

    local function cycle()
        local workspace = hl.get_active_workspace()
        local next_layout = core.next_layout(config, workspace.tiled_layout)
        apply_to_object(workspace, next_layout)
        if notify then
            announce(next_layout)
        end
        signal_waybar()
        verify_applied(workspace, next_layout)
    end

    -- Runtime layout changes are dropped on reload, so re-apply saved layouts on
    -- setup when sticky is enabled. Named entries with no live object stay pending.
    if sticky then
        if state_ok then
            ensure_dir(state_dir)
            local loaded, valid = read_state(state_file)
            if not valid then
                local recovered, recovered_valid = read_state(state_temp_file)
                if recovered_valid then
                    state = recovered
                    os.rename(state_temp_file, state_file)
                    chmod_file(state_file, "0600")
                end
            elseif loaded then
                state = loaded
            end
        end
        local filtered, invalid_workspaces = core.filter_state(state, config.cycle)
        state = filtered
        for _, key in ipairs(invalid_workspaces) do
            warn("saved layout for workspace " .. key .. " is no longer configured; removed")
        end
        if #invalid_workspaces > 0 then
            persist()
        end
        for key, layout in pairs(state) do
            local kind, identity = core.state_kind(key)
            if kind == "id" then
                apply_id(tonumber(identity), layout)
            elseif kind == "name" then
                local workspace = unique_named(identity)
                if workspace then
                    apply_to_object(workspace, layout)
                end
            end
        end
    end

    hl.bind(modifier .. " + " .. bind_key, cycle)
    if sticky then
        -- Re-apply after Hyprland creates or activates a window, since the
        -- default layout can replace the startup rule during app launch.
        -- workspace.created applies pending named entries once the object exists.
        hl.on("workspace.created", restore_workspace)
        hl.on("workspace.active", restore_active)
        hl.on("window.open", function()
            restore_workspace(hl.get_active_workspace())
            signal_waybar()
        end)
    else
        hl.on("workspace.active", signal_waybar)
    end
    hl.on("monitor.focused", signal_waybar)
end

return Swap
