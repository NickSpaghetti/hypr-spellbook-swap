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

-- hl.layout.register segfaults `Hyprland --verify-config` on 0.55.x (verify
-- loads the config but has no layout subsystem to register into). It works in
-- a real run, so register the custom layouts only in the nested instance --
-- run-nested.sh sets SBS_E2E=1 -- and skip it under `make verify`.
local register
if os.getenv("SBS_E2E") == "1" then
    register = dofile(repo .. "/src/custom_layouts.lua")
end

-- Wire the module with an isolated, throwaway state dir (test/.state).
local sb = dofile(repo .. "/src/spellbook_swap.lua")
sb.setup({
    state_dir = repo .. "/test/.state",
    register = register,
})
