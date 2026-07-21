-- Isolated Hyprland config for testing hypr-spellbook-swap. Loaded by
-- `make verify` (Hyprland --verify-config) and `make e2e` (nested instance).
-- Never touches ~/.config, the live session, or ~/.local/state: module state
-- goes to test/.state under the repo.
---@module 'hl'

-- Resolve the repo root from this file's own location (test/hyprland.lua),
-- without pattern matching, so the module loads by absolute path.
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
local repo = dir_of(dir_of(source))

-- Catch-all monitor so the nested/headless instance always has an output.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.config({
    general = {
        layout = "scrolling",
    },
})

-- A terminal bind to interact inside the nested instance, and a clean exit.
local terminal = os.getenv("TERMINAL") or "kitty"
hl.bind("SUPER + Q", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + SHIFT + Q", hl.dsp.exit())

local sb = dofile(repo .. "/src/init.lua")

-- hl.layout.register crashes `Hyprland --verify-config` on 0.55.x, and setup
-- registers the bundled custom layouts by default. So under `make verify`
-- (SBS_E2E unset) disable registration with register = {}; the nested run
-- (run-nested.sh sets SBS_E2E=1) uses the default and registers the grid layout.
local opts = { state_dir = repo .. "/test/.state" }
if os.getenv("SBS_E2E") ~= "1" then
    opts.register = {}
end
sb.setup(opts)
