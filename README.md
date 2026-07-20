# hypr-spellbook-swap

Cycle the focused Hyprland workspace between tiling layouts [scrolling](https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/), [dwindle](https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/), and [custom](https://wiki.hypr.land/Configuring/Layouts/Custom-Layouts/) layouts
on a keybind, with an optional notification and a Waybar layout indicator. A self contained Lua config module for Hyprland 0.55+.

## Development

```bash
make check   # stylua --check, luacheck, unit tests
make hooks   # enable the pre-commit hook (runs make check)
```

Requires: `luacheck`, `stylua` — `sudo pacman -S luacheck stylua`.
