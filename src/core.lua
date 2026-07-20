-- Pure layout-cycling logic: no `hl`, no io, no side effects. This is the
-- unit-tested surface; spellbook_swap.lua wires it to Hyprland.
--
-- `Core` is the module table: the set of functions this file exports. Callers
-- load it with `local core = dofile("core.lua")` and call `core.<fn>(...)`.
local Core = {}

-- Hyprland references a custom Lua layout as "lua:<name>" in config, but
-- reports the bare "<name>" at runtime.
-- https://wiki.hypr.land/Configuring/Layouts/Custom-Layouts/
local LUA_PREFIX = "lua:"

-- Strip the "lua:" reference prefix so a configured "lua:grid" matches the
-- runtime "grid".
local function bare_name(name)
    if name:sub(1, #LUA_PREFIX) == LUA_PREFIX then
        return name:sub(#LUA_PREFIX + 1)
    end
    return name
end

function Core.match_key(cycle, tiled_layout)
    for _, name in ipairs(cycle) do
        if name == tiled_layout or bare_name(name) == tiled_layout then
            return name
        end
    end
    return nil
end

function Core.next_layout(config, tiled_layout)
    local current = Core.match_key(config.cycle, tiled_layout)
    if not current then
        return config.default
    end
    local index = 1
    for position, name in ipairs(config.cycle) do
        if name == current then
            index = position
        end
    end
    return config.cycle[(index % #config.cycle) + 1]
end

function Core.resolve_flag(option_value, config_value)
    if option_value ~= nil then
        return option_value
    end
    if config_value ~= nil then
        return config_value
    end
    return false
end

function Core.icon_key(config, tiled_layout)
    if config.icons[tiled_layout] then
        return tiled_layout
    end
    return LUA_PREFIX .. tiled_layout
end

-- Build the Waybar custom-module state as a plain Lua table. Core stays
-- decoupled from Waybar's wire format: the I/O edge (waybar_emit.lua, C4)
-- serializes and escapes this to JSON.
function Core.waybar_state(config, tiled_layout)
    local key = Core.icon_key(config, tiled_layout)
    local label = (config.labels and config.labels[key]) or tiled_layout
    return {
        text = config.icons[key] or "?",
        tooltip = "Layout: " .. label,
    }
end

function Core.notify_send_cmd(label, icon)
    return string.format('notify-send -t 1500 -a hypr-spellbook-swap "Layout" "%s %s"', icon, label)
end

function Core.serialize_state(state)
    local lines = {}
    for workspace_id, layout in pairs(state) do
        lines[#lines + 1] = workspace_id .. "=" .. layout
    end
    table.sort(lines)
    if next(state) == nil then
        return ""
    end
    return table.concat(lines, "\n") .. "\n"
end

-- Parse the "<workspace_id>=<layout>" lines written by serialize_state, using
-- plain string search (no pattern matching): split each line on the first "=".
function Core.parse_state(text)
    local state = {}
    local pos = 1
    while pos <= #text do
        local newline = text:find("\n", pos, true)
        local line_end = newline and newline - 1 or #text
        local line = text:sub(pos, line_end)
        pos = line_end + 2

        local separator = line:find("=", 1, true)
        if separator then
            local workspace_id = tonumber(line:sub(1, separator - 1))
            local layout = line:sub(separator + 1)
            if workspace_id and layout ~= "" then
                state[workspace_id] = layout
            end
        end
    end
    return state
end

return Core
