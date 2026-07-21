-- Entry point for `require("hypr-spellbook-swap")` once installed under
-- ~/.config/hypr/. Self-locates its own directory so it works wherever it is
-- installed or symlinked, then loads the module and the bundled custom layouts
-- by path -- no fixed module name is baked in.
local function dir_of(path)
    for offset = #path, 1, -1 do
        if path:sub(offset, offset) == "/" then
            return path:sub(1, offset - 1)
        end
    end
    return "."
end

local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
    source = source:sub(2)
end
local here = dir_of(source)

local swap = dofile(here .. "/spellbook_swap.lua")
swap.custom_layouts = dofile(here .. "/custom_layouts.lua")
return swap
