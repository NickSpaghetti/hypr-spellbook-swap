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

-- Sticky state is tagged `id:<n>=<layout>` / `name:<name>=<layout>`.
-- `id:` is ours so Lua does not collapse t[2] and t["2"]. `name:` and
-- `special:` are Hyprland prefixes:
-- https://wiki.hypr.land/Configuring/Basics/Dispatchers/#workspace-selectors
-- https://wiki.hypr.land/Configuring/Basics/Dispatchers/#special-workspace
-- Lua has no encode or charset helpers, and we do not use patterns.
-- https://www.lua.org/manual/5.4/manual.html#pdf-string.format
-- https://www.lua.org/manual/5.4/manual.html#pdf-tonumber
local ID_PREFIX = "id:"
local NAME_PREFIX = "name:"
local SPECIAL_PREFIX = "special:"
-- Inclusive numeric IDs. Same Dispatchers section as name: / previous.
local MIN_WORKSPACE_ID = 1
local MAX_WORKSPACE_ID = 2147483647
-- Bytes that would break our `key=layout` lines.
local ENCODE_CHARS = "%=\n\r\0"
local HEX = "0123456789ABCDEFabcdef"
local DIGITS = "0123456789"
-- Wiki example is `name:Better anime`. Punctuation stays out so a name
-- cannot be a rule selector (`w[tv1]`, `m[DP-1]`, `r[2-4]`):
-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/#workspace-selectors
local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local NAME_CHARS = LETTERS .. DIGITS .. "._- "

-- Dispatcher tokens, not workspace names. `next` is in Hyprland's parser:
-- https://wiki.hypr.land/Configuring/Basics/Dispatchers/#workspace-selectors
-- https://github.com/hyprwm/Hyprland/blob/main/src/helpers/MiscFunctions.cpp
local RESERVED_NAMES = {
    previous = true,
    previous_per_monitor = true,
    empty = true,
    next = true,
    special = true,
}

local function has_char(s, ch)
    return s:find(ch, 1, true) ~= nil
end

function Core.percent_encode(text)
    local parts = {}
    for i = 1, #text do
        local ch = text:sub(i, i)
        if has_char(ENCODE_CHARS, ch) then
            parts[#parts + 1] = string.format("%%%02X", string.byte(ch))
        else
            parts[#parts + 1] = ch
        end
    end
    return table.concat(parts)
end

function Core.percent_decode(text)
    local parts = {}
    local i = 1
    while i <= #text do
        if text:sub(i, i) == "%" then
            local hex = text:sub(i + 1, i + 2)
            if
                #hex ~= 2
                or not has_char(HEX, hex:sub(1, 1))
                or not has_char(HEX, hex:sub(2, 2))
            then
                return nil
            end
            parts[#parts + 1] = string.char(tonumber(hex, 16))
            i = i + 3
        else
            parts[#parts + 1] = text:sub(i, i)
            i = i + 1
        end
    end
    return table.concat(parts)
end

local function charset_ok(s, allowed)
    for i = 1, #s do
        if not has_char(allowed, s:sub(i, i)) then
            return false
        end
    end
    return true
end

function Core.valid_workspace_name(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    if name:sub(1, #SPECIAL_PREFIX) == SPECIAL_PREFIX then
        name = name:sub(#SPECIAL_PREFIX + 1)
        if name == "" then
            return false
        end
    end
    if name:sub(1, 1) == " " or name:sub(#name, #name) == " " then
        return false
    end
    if RESERVED_NAMES[name] then
        return false
    end
    return has_char(LETTERS, name:sub(1, 1)) and charset_ok(name, NAME_CHARS)
end

local function parse_id(text)
    if text == "" or not charset_ok(text, DIGITS) then
        return nil
    end
    local n = tonumber(text, 10)
    if not n or n < MIN_WORKSPACE_ID or n > MAX_WORKSPACE_ID then
        return nil
    end
    return n
end

function Core.is_positive_workspace_id(id)
    return type(id) == "number"
        and id == math.floor(id)
        and id >= MIN_WORKSPACE_ID
        and id <= MAX_WORKSPACE_ID
end

function Core.state_kind(key)
    if type(key) ~= "string" then
        return nil
    end
    if key:sub(1, #ID_PREFIX) == ID_PREFIX then
        return "id", key:sub(#ID_PREFIX + 1)
    end
    if key:sub(1, #NAME_PREFIX) == NAME_PREFIX then
        return "name", key:sub(#NAME_PREFIX + 1)
    end
    return nil
end

function Core.id_key(id)
    return ID_PREFIX .. tostring(id)
end

function Core.name_key(name)
    return NAME_PREFIX .. name
end

function Core.persist_key(workspace)
    if not workspace then
        return nil
    end
    local id = workspace.id
    local name = workspace.name
    if workspace.special then
        if Core.valid_workspace_name(name) then
            return Core.name_key(name)
        end
        return nil
    end
    if type(name) == "string" and name ~= tostring(id) and Core.valid_workspace_name(name) then
        return Core.name_key(name)
    end
    if Core.is_positive_workspace_id(id) then
        return Core.id_key(id)
    end
    return nil
end

function Core.saved_layout(state, workspace)
    if not state or not workspace then
        return nil
    end
    local name = workspace.name
    if type(name) == "string" and name ~= "" then
        local by_name = state[Core.name_key(name)]
        if by_name then
            return by_name
        end
    end
    if workspace.id ~= nil then
        return state[Core.id_key(workspace.id)]
    end
    return nil
end

function Core.put_saved(state, workspace, layout)
    local key = Core.persist_key(workspace)
    if not key then
        return nil
    end
    local kind = Core.state_kind(key)
    if kind == "name" then
        if workspace.id ~= nil then
            state[Core.id_key(workspace.id)] = nil
        end
    elseif type(workspace.name) == "string" then
        state[Core.name_key(workspace.name)] = nil
    end
    state[key] = layout
    return key
end

-- Reject state_dir values that would break single-quoting into mkdir/chmod.
function Core.path_is_safe(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    return not has_char(path, "'") and not has_char(path, "\n") and not has_char(path, "\0")
end

function Core.serialize_state(state)
    local lines = {}
    for key, layout in pairs(state) do
        local kind, identity = Core.state_kind(key)
        if kind then
            lines[#lines + 1] = kind
                .. ":"
                .. Core.percent_encode(identity)
                .. "="
                .. Core.percent_encode(layout)
        end
    end
    table.sort(lines)
    if next(state) == nil then
        return ""
    end
    return table.concat(lines, "\n") .. "\n"
end

local function parse_state_line(line)
    local separator = line:find("=", 1, true)
    if not separator then
        return nil
    end
    local left = Core.percent_decode(line:sub(1, separator - 1))
    local layout = Core.percent_decode(line:sub(separator + 1))
    if not left or not layout or layout == "" then
        return nil
    end
    if has_char(layout, "=") or has_char(layout, "\n") or has_char(layout, "\r") or has_char(layout, "\0") then
        return nil
    end
    if left:sub(1, #ID_PREFIX) == ID_PREFIX then
        local id = parse_id(left:sub(#ID_PREFIX + 1))
        if not id then
            return nil
        end
        return Core.id_key(id), layout
    end
    if left:sub(1, #NAME_PREFIX) == NAME_PREFIX then
        local name = left:sub(#NAME_PREFIX + 1)
        if not Core.valid_workspace_name(name) then
            return nil
        end
        return Core.name_key(name), layout
    end
    return nil
end

-- Parse tagged `id:` / `name:` lines. Split on the first "=" with plain find.
-- Decode, then allowlist. One bad line makes the whole file invalid.
function Core.parse_state(text)
    local state = {}
    local valid = true
    local pos = 1
    while pos <= #text do
        local newline = text:find("\n", pos, true)
        local line_end = newline and newline - 1 or #text
        local line = text:sub(pos, line_end)
        pos = line_end + 2

        if line ~= "" then
            local key, layout = parse_state_line(line)
            if not key then
                valid = false
            else
                state[key] = layout
            end
        end
    end
    return state, valid
end

-- Keep saved layouts that still belong to the configured cycle. Removed or
-- renamed layouts are discarded so Hyprland can use its configured default.
function Core.filter_state(state, cycle)
    local filtered = {}
    local dropped = {}
    for key, layout in pairs(state) do
        if Core.match_key(cycle, layout) then
            filtered[key] = layout
        else
            dropped[#dropped + 1] = key
        end
    end
    return filtered, dropped
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
