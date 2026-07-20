-- Serialize Waybar custom-module state to JSON at the I/O edge. Core hands us
-- a plain table (core.waybar_state); we turn it into the JSON object Waybar's
-- custom module expects. Kept out of core.lua so the pure logic stays free of
-- wire-format concerns.
--
-- This is a minimal encoder for the flat string/number/boolean tables we emit
-- -- NOT a general JSON library. Values come from the user's layouts.lua
-- (labels can contain quotes), so strings are escaped.
local Waybar = {}

local SHORT_ESCAPES = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

-- Quote + escape a Lua string as a JSON string, walking it byte by byte (no
-- pattern matching). "\\" is handled via the table, so backslashes are escaped
-- before quotes; remaining control characters fall back to \uXXXX.
local function escape_string(str)
    local out = {}
    for offset = 1, #str do
        local char = str:sub(offset, offset)
        local short = SHORT_ESCAPES[char]
        if short then
            out[#out + 1] = short
        elseif char < " " then
            out[#out + 1] = string.format("\\u%04x", string.byte(char))
        else
            out[#out + 1] = char
        end
    end
    return '"' .. table.concat(out) .. '"'
end

-- Encode a flat table of string/number/boolean values as a JSON object. Keys
-- are sorted so the output is deterministic (and testable).
function Waybar.encode(object)
    local keys = {}
    for key in pairs(object) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
        local value = object[key]
        local encoded
        if type(value) == "string" then
            encoded = escape_string(value)
        else
            encoded = tostring(value) -- number or boolean
        end
        parts[#parts + 1] = escape_string(key) .. ":" .. encoded
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

return Waybar
