-- Default layout configuration. Users override any field via sb.setup(opts).
-- Icons are PUA glyphs from the bundled "hypr-spellbook-swap-layouts" font,
-- written as UTF-8 byte escapes because LuaJIT has no \u{} string escape.
return {
    notify = false,
    sticky = false,
    notification_engine = "hyprland", -- "hyprland" (native overlay) | "sway" (notify-send)
    default = "scrolling",
    cycle = { "scrolling", "dwindle", "lua:grid" },
    icons = {
        ["scrolling"] = "\238\164\130", -- U+E902
        ["dwindle"] = "\238\164\128", -- U+E900
        ["master"] = "\238\164\129", -- U+E901
        ["lua:grid"] = "\238\164\132", -- U+E904 custom font
    },
    labels = {
        ["scrolling"] = "Scrolling",
        ["dwindle"] = "Dwindle",
        ["master"] = "Master",
        ["lua:grid"] = "Grid (custom)",
    },
}
