-- Executable entry for Waybar's custom module: prints the current layout as a
-- JSON object on stdout. Invoked by scripts/waybar-layout.sh with the active
-- tiled layout in arg[1]. Finds its siblings by its own directory so no path
-- is hardcoded.
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
local REPO = dir_of(source)

local core = dofile(REPO .. "/core.lua")
local waybar = dofile(REPO .. "/waybar.lua")
local config = dofile(REPO .. "/layouts.lua")

-- _G.arg (not a bare `arg`) so luacheck doesn't flag the CLI arg table.
local argv = _G.arg or {}
io.write(waybar.encode(core.waybar_state(config, argv[1] or "")))
