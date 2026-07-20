-- Hyprland glue for the layout-cycling feature. This is the thin I/O layer:
-- it wires the pure logic in core.lua to Hyprland's `hl` API (binds, events,
-- workspace rules, notifications) and to on-disk state. All decisions live in
-- core.
--
-- `Swap` is the module table exported by this file. Load it by absolute path
-- (the repo is not on Hyprland's require path): https://hypr.land/news/26_lua/
--   local sb = dofile("/path/to/hypr-spellbook-swap/spellbook_swap.lua")
--   sb.setup({ ... })
local Swap = {}

-- Directory containing this file, found without pattern matching so we can
-- dofile core.lua / layouts.lua by absolute path.
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

local REPO = script_dir()
local core = dofile(REPO .. "/core.lua")

function Swap.setup(opts)
    opts = opts or {}
    local config = opts.layouts or assert(loadfile(opts.layouts_path or (REPO .. "/layouts.lua")))()

    local notify = core.resolve_flag(opts.notify, config.notify)
    local sticky = core.resolve_flag(opts.sticky, config.sticky)
    local engine = opts.notification_engine or config.notification_engine or "hyprland"
    local signal = opts.waybar_signal or config.waybar_signal or 8
    local modifier = opts.mod or config.mod or "SUPER"
    local key = opts.key or config.key or "L"

    local state_dir = opts.state_dir or (os.getenv("HOME") .. "/.local/state/hypr-spellbook-swap")
    local state_file = state_dir .. "/layouts"
    local state = {} -- workspace id -> layout name

    for name, provider in pairs(opts.register or config.register or {}) do
        hl.layout.register(name, provider)
    end

    -- Switch a workspace's tiled layout. Setting the workspace rule re-tiles it
    -- immediately. We do NOT use `hyprctl keyword`: it is rejected under a lua
    -- config ("keyword can't work with non-legacy parsers; use eval"). The
    -- workspace selector must be a string.
    local function apply(workspace_id, layout)
        hl.workspace_rule({ workspace = tostring(workspace_id), layout = layout })
    end

    local function persist()
        os.execute('mkdir -p "' .. state_dir .. '"')
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
        local icon_key = core.icon_key(config, layout)
        local icon = (config.icons and config.icons[icon_key]) or "?"
        local label = (config.labels and config.labels[icon_key]) or layout
        if engine == "sway" then
            hl.exec_cmd(core.notify_send_cmd(label, icon))
        else
            hl.notification.create({ text = label, icon = "ok", timeout = 1500 })
        end
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
    end

    -- Runtime layout changes are dropped on config reload, so re-apply the
    -- saved layout for each workspace on setup when sticky is enabled.
    -- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
    if sticky then
        os.execute('mkdir -p "' .. state_dir .. '"')
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
