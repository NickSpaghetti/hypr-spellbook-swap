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

-- Resolve the icon glyph and human label for a layout, with fallbacks ("?" icon,
-- the layout name as label). Shared by the notification and the Waybar edge.
function Core.icon_and_label(config, layout)
    local key = Core.icon_key(config, layout)
    local icon = (config.icons and config.icons[key]) or "?"
    local label = (config.labels and config.labels[key]) or layout
    return icon, label
end

-- Build the Waybar custom-module state as a plain Lua table. Core stays
-- decoupled from Waybar's wire format: the I/O edge (waybar_emit.lua) serializes
-- and escapes this to JSON.
function Core.waybar_state(config, tiled_layout)
    local icon, label = Core.icon_and_label(config, tiled_layout)
    return {
        text = icon,
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

-- Does a layout name refer to a custom Lua layout ("lua:<name>")?
function Core.is_lua_layout(name)
    return name:sub(1, #LUA_PREFIX) == LUA_PREFIX
end

-- The set of valid custom (lua:) layout names: the register keys plus any extras
-- the user declares (lua: layouts registered outside this module). Built-in and
-- plugin names are NOT tracked -- Hyprland owns that namespace and gives no way
-- to enumerate it, so bare names pass through and the runtime read-back catches
-- one that does not actually apply.
function Core.valid_lua_layouts(register, extra)
    local set = {}
    for name in pairs(register or {}) do
        set[LUA_PREFIX .. name] = true
    end
    for _, name in ipairs(extra or {}) do
        set[name] = true
    end
    return set
end

-- Keep every bare name; drop only lua: entries that are not registered.
function Core.filter_cycle(cycle, valid_lua)
    local kept, dropped = {}, {}
    for _, name in ipairs(cycle) do
        if Core.is_lua_layout(name) and not valid_lua[name] then
            dropped[#dropped + 1] = name
        else
            kept[#kept + 1] = name
        end
    end
    return kept, dropped
end

-- Serialize a string->string map to a Lua table literal, keys sorted for
-- deterministic output. string.format("%q") makes each entry round-trip.
local function serialize_string_map(map)
    local keys = {}
    for name in pairs(map or {}) do
        keys[#keys + 1] = name
    end
    table.sort(keys)
    local parts = {}
    for _, name in ipairs(keys) do
        parts[#parts + 1] = string.format("        [%q] = %q,", name, map[name])
    end
    return "{\n" .. table.concat(parts, "\n") .. "\n    }"
end

-- Serialize the effective icons/labels to a loadable Lua chunk. sb.setup writes
-- this so the out-of-process Waybar emit reads the SAME config you configured,
-- not just the shipped defaults.
function Core.serialize_config(config)
    return "return {\n    icons = "
        .. serialize_string_map(config.icons)
        .. ",\n    labels = "
        .. serialize_string_map(config.labels)
        .. ",\n}\n"
end

return Core
