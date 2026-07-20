-- Example custom Lua layout providers, passed to sb.setup{ register = ... }.
-- Each is registered via hl.layout.register(name, provider) and referenced as
-- "lua:<name>". https://wiki.hypr.land/Configuring/Layouts/Custom-Layouts/
return {
    grid = {
        recalculate = function(ctx)
            local count = #ctx.targets
            if count == 0 then
                return
            end
            local cols = math.ceil(math.sqrt(count))
            local rows = math.ceil(count / cols)
            for index, target in ipairs(ctx.targets) do
                target:place(ctx:grid_cell(index - 1, cols, rows))
            end
        end,
    },
}
