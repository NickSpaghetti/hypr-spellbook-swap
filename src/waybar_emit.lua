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

-- Prefer the effective config sb.setup persisted (so your setup opts -- icons,
-- labels -- reach the bar). SBS_WAYBAR_CONFIG overrides the path (tests). Fall
-- back to the shipped defaults until the first setup has run.
local function load_config()
    local path = os.getenv("SBS_WAYBAR_CONFIG")
    if not path or path == "" then
        path = (os.getenv("HOME") or "") .. "/.local/state/hypr-spellbook-swap/waybar.lua"
    end
    local loaded, config = pcall(dofile, path)
    if loaded and type(config) == "table" then
        return config
    end
    return dofile(REPO .. "/layouts.lua")
end

-- _G.arg (not a bare `arg`) so luacheck doesn't flag the CLI arg table.
local argv = _G.arg or {}
io.write(waybar.encode(core.waybar_state(load_config(), argv[1] or "")))
