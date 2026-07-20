-- Unit tests for core.lua (pure logic). Run via `make test`, i.e.
-- `lua spec/core_spec.lua` from the repo root, so both files load by path.
local ok = dofile("spec/support.lua")
local core = dofile("src/core.lua")

local mock_layout_config = {
    default = "scrolling",
    cycle = { "scrolling", "dwindle", "lua:grid" },
    icons = { scrolling = "S", dwindle = "D", ["lua:grid"] = "G" },
    labels = { scrolling = "Scrolling", dwindle = "Dwindle", ["lua:grid"] = "Grid" },
}

ok.eq(core.next_layout(mock_layout_config, "scrolling"), "dwindle")
ok.eq(core.next_layout(mock_layout_config, "dwindle"), "lua:grid")
ok.eq(core.next_layout(mock_layout_config, "grid"), "scrolling") -- wrap; custom layout reported bare
ok.eq(core.next_layout(mock_layout_config, "unknown"), "scrolling") -- unknown -> default
ok.eq(core.match_key(mock_layout_config.cycle, "grid"), "lua:grid")
ok.eq(core.resolve_flag(nil, nil), false)
ok.eq(core.resolve_flag(true, false), true)
ok.eq(core.resolve_flag(nil, true), true)
ok.eq(core.icon_key(mock_layout_config, "grid"), "lua:grid")

-- waybar_state returns a plain table (the edge serializes it to JSON, C4)
local waybar = core.waybar_state(mock_layout_config, "dwindle")
ok.eq(waybar.text, "D")
ok.eq(waybar.tooltip, "Layout: Dwindle")

-- unknown layout: fall back to "?" icon and the bare name in the tooltip
local unknown = core.waybar_state(mock_layout_config, "unknown")
ok.eq(unknown.text, "?")
ok.eq(unknown.tooltip, "Layout: unknown")

ok.eq(core.parse_state(core.serialize_state({ [2] = "dwindle" }))[2], "dwindle")
ok.done()
