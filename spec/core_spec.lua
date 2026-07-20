-- Unit tests for core.lua (pure logic). Run via `make test`, i.e.
-- `lua spec/core_spec.lua` from the repo root, so both files load by path.
local ok = dofile("spec/support.lua")
local core = dofile("core.lua")

local cfg = {
    default = "scrolling",
    cycle = { "scrolling", "dwindle", "lua:grid" },
    icons = { scrolling = "S", dwindle = "D", ["lua:grid"] = "G" },
    labels = { scrolling = "Scrolling", dwindle = "Dwindle", ["lua:grid"] = "Grid" },
}

ok.eq(core.next_layout(cfg, "scrolling"), "dwindle")
ok.eq(core.next_layout(cfg, "dwindle"), "lua:grid")
ok.eq(core.next_layout(cfg, "grid"), "scrolling") -- wrap; custom layout reported bare
ok.eq(core.next_layout(cfg, "unknown"), "scrolling") -- unknown -> default
ok.eq(core.match_key(cfg.cycle, "grid"), "lua:grid")
ok.eq(core.resolve_flag(nil, nil), false)
ok.eq(core.resolve_flag(true, false), true)
ok.eq(core.resolve_flag(nil, true), true)
ok.eq(core.icon_key(cfg, "grid"), "lua:grid")

-- waybar_state returns a plain table (the edge serializes it to JSON, C4)
local waybar = core.waybar_state(cfg, "dwindle")
ok.eq(waybar.text, "D")
ok.eq(waybar.tooltip, "Layout: Dwindle")

-- unknown layout: fall back to "?" icon and the bare name in the tooltip
local unknown = core.waybar_state(cfg, "unknown")
ok.eq(unknown.text, "?")
ok.eq(unknown.tooltip, "Layout: unknown")

ok.eq(core.parse_state(core.serialize_state({ [2] = "dwindle" }))[2], "dwindle")
ok.done()
