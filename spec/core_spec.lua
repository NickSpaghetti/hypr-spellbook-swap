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

-- percent-encode reserved bytes only; valid names/layouts stay readable
ok.eq(core.percent_encode("coding"), "coding")
ok.eq(core.percent_encode("lua:grid"), "lua:grid")
ok.eq(core.percent_encode("="), "%3D")
ok.eq(core.percent_encode("%"), "%25")
ok.eq(core.percent_decode("lua:grid"), "lua:grid")
ok.eq(core.percent_decode("foo%3Dbar"), "foo=bar")
ok.eq(core.percent_decode("%25"), "%")
ok.eq(core.percent_decode("%"), nil)
ok.eq(core.percent_decode("%3"), nil)
ok.eq(core.percent_decode("%GG"), nil)

ok.eq(core.valid_workspace_name("coding"), true)
ok.eq(core.valid_workspace_name("Better anime"), true)
ok.eq(core.valid_workspace_name("special:magic"), true)
ok.eq(core.valid_workspace_name("w[tv1]"), false)
ok.eq(core.valid_workspace_name("m:desc:x"), false)
ok.eq(core.valid_workspace_name("+1"), false)
ok.eq(core.valid_workspace_name("n[s:a]"), false)
ok.eq(core.valid_workspace_name("previous"), false)
ok.eq(core.valid_workspace_name("2"), false)
ok.eq(core.valid_workspace_name(""), false)

local long = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" -- 65
ok.eq(#long, 65)
ok.eq(core.valid_workspace_name(long), true)

ok.eq(core.persist_key({ id = 2, name = "2" }), "id:2")
ok.eq(core.persist_key({ id = 5, name = "coding" }), "name:coding")
ok.eq(core.persist_key({ id = -98, name = "special:magic", special = true }), "name:special:magic")

local saved_state = { ["id:2"] = "dwindle", ["name:coding"] = "scrolling" }
ok.eq(core.saved_layout(saved_state, { id = 5, name = "coding" }), "scrolling")
ok.eq(core.saved_layout(saved_state, { id = 2, name = "2" }), "dwindle")

local put = {}
core.put_saved(put, { id = 5, name = "coding" }, "scrolling")
ok.eq(put["name:coding"], "scrolling")
ok.eq(put["id:5"], nil)
core.put_saved(put, { id = 5, name = "5" }, "dwindle")
ok.eq(put["id:5"], "dwindle")
ok.eq(put["name:coding"], "scrolling")
ok.eq(put["name:5"], nil)

ok.eq(core.path_is_safe("/tmp/hypr-spellbook-swap"), true)
ok.eq(core.path_is_safe("/tmp/foo'bar"), false)

local parsed, valid = core.parse_state(core.serialize_state({ ["id:2"] = "dwindle" }))
ok.eq(parsed["id:2"], "dwindle")
ok.eq(valid, true)

local mixed, mixed_valid = core.parse_state(core.serialize_state({
    ["id:2"] = "dwindle",
    ["name:coding"] = "scrolling",
    ["name:browser"] = "lua:grid",
}))
ok.eq(mixed_valid, true)
ok.eq(mixed["id:2"], "dwindle")
ok.eq(mixed["name:coding"], "scrolling")
ok.eq(mixed["name:browser"], "lua:grid")

local encoded_layout, encoded_ok = core.parse_state(core.serialize_state({ ["id:2"] = "100%" }))
ok.eq(encoded_ok, true)
ok.eq(encoded_layout["id:2"], "100%")

local _, invalid = core.parse_state("not-state\n")
ok.eq(invalid, false)
local _, untagged = core.parse_state("2=dwindle\n")
ok.eq(untagged, false)
local _, bad_id = core.parse_state("id:0=dwindle\n")
ok.eq(bad_id, false)
local _, neg_id = core.parse_state("id:-1=dwindle\n")
ok.eq(neg_id, false)
local _, sci_id = core.parse_state("id:1e2=dwindle\n")
ok.eq(sci_id, false)
local _, selector_name = core.parse_state("name:w[tv1]=dwindle\n")
ok.eq(selector_name, false)
local _, monitor_name = core.parse_state("name:m:desc:x=dwindle\n")
ok.eq(monitor_name, false)
local _, relative_name = core.parse_state("name:+1=dwindle\n")
ok.eq(relative_name, false)
local _, prefix_name = core.parse_state("name:n[s:a]=dwindle\n")
ok.eq(prefix_name, false)
local _, encoded_eq = core.parse_state("name:foo%3Dbar=dwindle\n")
ok.eq(encoded_eq, false)

local special_parsed, special_ok = core.parse_state("name:special:magic=scrolling\n")
ok.eq(special_ok, true)
ok.eq(special_parsed["name:special:magic"], "scrolling")

local filtered, state_dropped =
    core.filter_state({ ["id:2"] = "dwindle", ["id:3"] = "removed" }, mock_layout_config.cycle)
ok.eq(filtered["id:2"], "dwindle")
ok.eq(filtered["id:3"], nil)
ok.eq(#state_dropped, 1)
ok.eq(state_dropped[1], "id:3")
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
