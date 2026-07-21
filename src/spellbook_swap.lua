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

local function ensure_dir(path)
    os.execute('mkdir -p "' .. path .. '"')
end

local REPO = script_dir()
local core = dofile(REPO .. "/core.lua")

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
    local key = opts.key or config.key or "L"

    local state_dir = opts.state_dir or (os.getenv("HOME") .. "/.local/state/hypr-spellbook-swap")
    local state_file = state_dir .. "/layouts"
    local state = {} -- workspace id -> layout name

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
    ensure_dir(state_dir)
    local waybar_file = io.open(state_dir .. "/waybar.lua", "w")
    if waybar_file then
        waybar_file:write(core.serialize_config(config))
        waybar_file:close()
    end

    local function apply(workspace_id, layout)
        hl.workspace_rule({ workspace = tostring(workspace_id), layout = layout })
    end

    local function persist()
        ensure_dir(state_dir)
        local file = io.open(state_file, "w")
        if file then
            file:write(core.serialize_state(state))
            file:close()
        end
    end

    local function signal_waybar()
        hl.exec_cmd("pkill -RTMIN+" .. signal .. " waybar")
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
    local function verify_applied(workspace_id, requested)
        if not hl.timer then
            return
        end
        local timer
        timer = hl.timer(function()
            if timer and timer.set_enabled then
                timer:set_enabled(false)
            end
            local workspace = hl.get_active_workspace()
            if
                workspace
                and workspace.id == workspace_id
                and workspace.tiled_layout ~= requested
            then
                warn(
                    "layout '"
                        .. requested
                        .. "' did not apply (now '"
                        .. tostring(workspace.tiled_layout)
                        .. "'); is it available?"
                )
            end
        end, { timeout = 100, type = "repeat" })
    end

    local function cycle()
        local workspace = hl.get_active_workspace()
        local next_layout = core.next_layout(config, workspace.tiled_layout)
        apply(workspace.id, next_layout)
        state[workspace.id] = next_layout
        persist()
        if notify then
            announce(next_layout)
        end
        signal_waybar()
        verify_applied(workspace.id, next_layout)
    end

    -- Runtime layout changes are dropped on reload, so re-apply saved layouts on
    -- setup when sticky is enabled.
    if sticky then
        ensure_dir(state_dir)
        local file = io.open(state_file, "r")
        if file then
            state = core.parse_state(file:read("*a"))
            file:close()
            for workspace_id, layout in pairs(state) do
                apply(workspace_id, layout)
            end
        end
    end

    hl.bind(modifier .. " + " .. key, cycle)
    hl.on("workspace.active", signal_waybar)
    hl.on("monitor.focused", signal_waybar)
end

return Swap
