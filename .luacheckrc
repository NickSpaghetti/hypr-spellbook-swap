std = "max"
read_globals = { "hl" }

-- Dependency/tool trees the CI Lua + LuaRocks actions install into the
-- workspace (leafo/gh-actions-lua -> .lua, gh-actions-luarocks -> .luarocks).
-- These are not project source; stylua skips them as hidden dirs, but luacheck
-- walks them unless excluded.
exclude_files = {
    ".lua/**/*.lua",
    ".luarocks/**/*.lua",
    ".install/**/*.lua",
}

files["spec/glue_spec.lua"].globals = { "hl" }
