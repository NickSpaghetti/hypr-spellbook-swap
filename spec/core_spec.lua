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
-- is_lua_layout: only "lua:" names are custom
ok.eq(core.is_lua_layout("lua:grid"), true)
ok.eq(core.is_lua_layout("dwindle"), false)

-- valid_lua_layouts: register keys (as lua:) + declared lua: extras; no built-ins
local valid_lua = core.valid_lua_layouts({ grid = {} }, { "lua:foo" })
ok.eq(valid_lua["lua:grid"], true)
ok.eq(valid_lua["lua:foo"], true)
ok.eq(valid_lua.dwindle, nil)

-- filter_cycle: bare names always kept; only unregistered lua: entries dropped
local kept, dropped =
    core.filter_cycle({ "scrolling", "master", "lua:grid", "lua:nope" }, valid_lua)
ok.eq(#kept, 3)
ok.eq(kept[1], "scrolling")
ok.eq(kept[2], "master")
ok.eq(kept[3], "lua:grid")
ok.eq(#dropped, 1)
ok.eq(dropped[1], "lua:nope")

-- serialize_config round-trips icons/labels (persisted for the waybar emit)
local dumped = core.serialize_config({
    icons = { ["lua:grid"] = "\238\164\132", scrolling = "S" },
    labels = { scrolling = "Scrolling" },
})
local roundtrip = (loadstring or load)(dumped)()
ok.eq(roundtrip.icons["lua:grid"], "\238\164\132")
ok.eq(roundtrip.icons.scrolling, "S")
ok.eq(roundtrip.labels.scrolling, "Scrolling")

-- icon_and_label: glyph + label, falling back to "?" and the raw name
local mock = { icons = { dwindle = "D" }, labels = { dwindle = "Dwindle" } }
local icon, label = core.icon_and_label(mock, "dwindle")
ok.eq(icon, "D")
ok.eq(label, "Dwindle")
local micon, mlabel = core.icon_and_label(mock, "mystery")
ok.eq(micon, "?")
ok.eq(mlabel, "mystery")

ok.done()
