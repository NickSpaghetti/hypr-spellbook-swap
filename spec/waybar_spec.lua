-- Unit tests for src/waybar.lua (the JSON-object encoder used to emit Waybar
-- state) plus an end-to-end check of src/waybar_emit.lua. Run via `make test`.
local ok = dofile("spec/support.lua")
local waybar = dofile("src/waybar.lua")

-- basic object, keys sorted for deterministic output
ok.eq(
    waybar.encode({ text = "D", tooltip = "Layout: Dwindle" }),
    '{"text":"D","tooltip":"Layout: Dwindle"}'
)
ok.eq(waybar.encode({ b = "2", a = "1" }), '{"a":"1","b":"2"}')

-- string escaping: backslash escaped before quote, both survive
ok.eq(waybar.encode({ text = 'a"b\\c' }), '{"text":"a\\"b\\\\c"}')

-- control characters use their short escapes (real tab -> \t)
ok.eq(waybar.encode({ text = "tab\there" }), '{"text":"tab\\there"}')

-- end-to-end: the emit script loads the real layouts.lua + core + waybar and
-- prints valid JSON. dwindle icon is U+E900 = bytes \238\164\128.
local handle = io.popen("lua src/waybar_emit.lua dwindle")
local output = handle:read("*a")
handle:close()
ok.eq(output, '{"text":"\238\164\128","tooltip":"Layout: Dwindle"}')

ok.done()
