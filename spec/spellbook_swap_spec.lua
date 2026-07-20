-- Unit tests for spellbook_swap.lua against a fake `hl` and a temp state dir.
-- Run via `make test`, i.e. `lua spec/spellbook_swap_spec.lua` from the repo root.
local ok = dofile("spec/support.lua")

local mock_layout_config = {
    default = "scrolling",
    cycle = { "scrolling", "dwindle", "lua:grid" },
    icons = { scrolling = "S", dwindle = "D", ["lua:grid"] = "G" },
    labels = { scrolling = "Scrolling", dwindle = "Dwindle", ["lua:grid"] = "Grid" },
}

-- Fresh fake `hl` that records everything the glue asks Hyprland to do.
local function fake_hl(tiled_layout)
    local calls =
        { exec = {}, rules = {}, notifications = {}, binds = {}, events = {}, registered = {} }
    _G.hl = {
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

local sb = dofile("src/spellbook_swap.lua")

local shared_dir = fresh_state_dir()

-- 1) setup wires a bind + the workspace/monitor events
local calls = fake_hl("scrolling")
sb.setup({ layouts = mock_layout_config, state_dir = shared_dir, notify = false })
ok.eq(#calls.binds, 1)
ok.eq(calls.binds[1].combo, "SUPER + L")
ok.eq(#calls.events, 2)

-- cycle() switches the workspace to the NEXT layout (scrolling -> dwindle) via
-- a workspace rule, with the id as a string
local cycle = last(calls.binds).fn
cycle()
ok.eq(last(calls.rules).workspace, "2")
ok.eq(last(calls.rules).layout, "dwindle")

-- 2) notify=false records no notification (neither engine path runs)
ok.eq(#calls.notifications, 0)

-- 3) engine="sway" emits a notify-send exec, not an hl notification
calls = fake_hl("scrolling")
sb.setup({
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
sb.setup({ layouts = mock_layout_config, state_dir = shared_dir, notify = true })
last(calls.binds).fn()
ok.eq(#calls.notifications, 1)

-- 5) sticky: cycle persists state, and a fresh setup re-applies it
local sticky_dir = fresh_state_dir()
local first = fake_hl("scrolling")
sb.setup({ layouts = mock_layout_config, state_dir = sticky_dir, sticky = true, notify = false })
last(first.binds).fn() -- ws 2 -> dwindle, persisted to sticky_dir
local second = fake_hl("scrolling")
sb.setup({ layouts = mock_layout_config, state_dir = sticky_dir, sticky = true, notify = false })
ok.eq(second.rules[1].workspace, "2")
ok.eq(second.rules[1].layout, "dwindle")

os.execute('rm -rf "' .. shared_dir .. '" "' .. sticky_dir .. '"')
ok.done()
