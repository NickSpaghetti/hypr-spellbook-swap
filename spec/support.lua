-- Tiny zero-dependency test harness (no busted). Each spec `dofile`s this,
-- asserts with ok.eq(got, want), and ends with ok.done() to report and exit.
local M = {}

local passed = 0
local failures = {}

local function show(v)
    if type(v) == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

function M.eq(got, want)
    if got == want then
        passed = passed + 1
    else
        failures[#failures + 1] = string.format("expected %s, got %s", show(want), show(got))
    end
end

function M.done()
    print(string.format("%d passed, %d failed", passed, #failures))
    for _, msg in ipairs(failures) do
        print("  not ok: " .. msg)
    end
    if #failures > 0 then
        os.exit(1)
    end
end

return M
