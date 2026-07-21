-- Unit tests for spellbook_swap.lua against a fake `hl` and a temp state dir.
-- Run via `make test`, i.e. `lua spec/spellbook_swap_spec.lua` from the repo root.
local ok = dofile("spec/support.lua")

local mock_layout_config = {
    default = "scrolling",
    cycle = { "scrolling", "dwindle", "lua:grid" },
    icons = { scrolling = "S", dwindle = "D", ["lua:grid"] = "G" },
    labels = { scrolling = "Scrolling", dwindle = "Dwindle", ["lua:grid"] = "Grid" },
}

-- Fresh fake `hl` that records everything the glue asks Hyprland to do. The
-- fake is passed to setup via opts.hl, so no global is touched.
local function fake_hl(tiled_layout)
    local calls = {
        exec = {},
        rules = {},
        notifications = {},
        binds = {},
        events = {},
        registered = {},
        timers = {},
    }
    calls.hl = {
        get_active_workspace = function()
            return { id = 2, tiled_layout = tiled_layout }
        end,
        exec_cmd = function(cmd)
            calls.exec[#calls.exec + 1] = cmd
        end,
        workspace_rule = function(rule)
            calls.rules[#calls.rules + 1] = rule
        end,
        notification = {
            create = function(spec)
                calls.notifications[#calls.notifications + 1] = spec
            end,
        },
        bind = function(combo, fn)
            calls.binds[#calls.binds + 1] = { combo = combo, fn = fn }
        end,
        on = function(event, fn)
            calls.events[#calls.events + 1] = { event = event, fn = fn }
        end,
        layout = {
            register = function(name, provider)
                calls.registered[name] = provider
            end,
        },
        timer = function(fn)
            calls.timers[#calls.timers + 1] = fn
            return { set_enabled = function() end }
        end,
    }
    return calls
end

local function last(list)
    return list[#list]
end

local function contains(list, needle)
    for _, value in ipairs(list) do
        if value == needle then
            return true
        end
    end
    return false
end

local function fresh_state_dir()
    local path = os.tmpname() -- creates a temp file; we want a fresh dir path
    os.remove(path)
    return path .. ".sbs"
end

local function noop() end

local sb = dofile("src/spellbook_swap.lua")

local shared_dir = fresh_state_dir()

-- 1) setup wires a bind + the workspace/monitor events, and registers the
--    bundled custom layout by default (no explicit register passed)
local calls = fake_hl("scrolling")
sb.setup({ hl = calls.hl, layouts = mock_layout_config, state_dir = shared_dir, notify = false })
ok.eq(#calls.binds, 1)
ok.eq(calls.binds[1].combo, "SUPER + L")
ok.eq(#calls.events, 2)
ok.eq(calls.registered.grid ~= nil, true)

-- cycle() switches the workspace to the NEXT layout via a workspace rule, with
-- the id as a string
local cycle = last(calls.binds).fn
cycle()
ok.eq(last(calls.rules).workspace, "2")
ok.eq(last(calls.rules).layout, "dwindle")

-- 2) notify=false records no notification
ok.eq(#calls.notifications, 0)

-- 3) engine="sway" emits a notify-send exec, not an hl notification
calls = fake_hl("scrolling")
sb.setup({
    hl = calls.hl,
    layouts = mock_layout_config,
    state_dir = shared_dir,
    notify = true,
    notification_engine = "sway",
})
last(calls.binds).fn()
ok.eq(contains(calls.exec, 'notify-send -t 1500 -a hypr-spellbook-swap "Layout" "D Dwindle"'), true)
ok.eq(#calls.notifications, 0)

-- 4) engine="hyprland" (default) calls hl.notification.create
calls = fake_hl("scrolling")
sb.setup({ hl = calls.hl, layouts = mock_layout_config, state_dir = shared_dir, notify = true })
last(calls.binds).fn()
ok.eq(#calls.notifications, 1)

-- 5) register = {} disables custom-layout registration (warn silenced: with no
--    grid registered, lua:grid in the mock cycle is legitimately dropped)
local none = fake_hl("scrolling")
sb.setup({
    hl = none.hl,
    warn = noop,
    layouts = mock_layout_config,
    state_dir = shared_dir,
    register = {},
    notify = false,
})
ok.eq(next(none.registered), nil)

-- 6) setup with no hl (opts.hl absent and no global) errors clearly
ok.eq(
    pcall(function()
        sb.setup({ layouts = mock_layout_config, state_dir = shared_dir })
    end),
    false
)

-- 7) opts.cycle overrides the config's cycle
local override = fake_hl("scrolling")
sb.setup({
    hl = override.hl,
    layouts = mock_layout_config,
    state_dir = shared_dir,
    cycle = { "scrolling", "master" },
    notify = false,
})
last(override.binds).fn()
ok.eq(last(override.rules).layout, "master")

-- 8) an unregistered lua: layout in the cycle is dropped with a warning; bare
--    names are always kept
local a1warn = {}
local a1 = fake_hl("scrolling")
sb.setup({
    hl = a1.hl,
    warn = function(m)
        a1warn[#a1warn + 1] = m
    end,
    layouts = mock_layout_config,
    state_dir = shared_dir,
    cycle = { "scrolling", "lua:nope", "dwindle" },
    notify = false,
})
last(a1.binds).fn() -- "lua:nope" dropped: scrolling -> dwindle
ok.eq(last(a1.rules).layout, "dwindle")
ok.eq(#a1warn, 1)

-- 9) verify_applied warns when the layout does not actually take (readback differs)
local bwarn = {}
local bv = fake_hl("scrolling") -- get_active_workspace always reports "scrolling"
sb.setup({
    hl = bv.hl,
    warn = function(m)
        bwarn[#bwarn + 1] = m
    end,
    layouts = mock_layout_config,
    state_dir = shared_dir,
    notify = false,
})
last(bv.binds).fn() -- requests "dwindle"; the fake still reports "scrolling"
last(bv.timers)() -- fire the deferred read-back check
ok.eq(#bwarn, 1)

-- 10) sticky: cycle persists state, and a fresh setup re-applies it
local sticky_dir = fresh_state_dir()
local first = fake_hl("scrolling")
sb.setup({
    hl = first.hl,
    layouts = mock_layout_config,
    state_dir = sticky_dir,
    sticky = true,
    notify = false,
})
last(first.binds).fn() -- ws 2 -> dwindle, persisted to sticky_dir
local second = fake_hl("scrolling")
sb.setup({
    hl = second.hl,
    layouts = mock_layout_config,
    state_dir = sticky_dir,
    sticky = true,
    notify = false,
})
ok.eq(second.rules[1].workspace, "2")
ok.eq(second.rules[1].layout, "dwindle")

-- 11) setup persists the effective (merged) icons/labels for the waybar emit
local pdir = fresh_state_dir()
local pv = fake_hl("scrolling")
sb.setup({
    hl = pv.hl,
    layouts = mock_layout_config,
    state_dir = pdir,
    icons = { ["lua:my-foo"] = "F" },
    notify = false,
})
local persisted = (loadstring or load)(io.open(pdir .. "/waybar.lua"):read("*a"))()
ok.eq(persisted.icons["lua:my-foo"], "F")
ok.eq(persisted.icons.scrolling, "S")
os.execute('rm -rf "' .. pdir .. '"')

os.execute('rm -rf "' .. shared_dir .. '" "' .. sticky_dir .. '"')
ok.done()
