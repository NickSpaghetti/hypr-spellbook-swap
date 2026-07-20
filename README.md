# hypr-spellbook-swap

Cycle the focused Hyprland workspace between tiling layouts (scrolling, dwindle, custom `lua:` layouts)
on a keybind, with an optional notification and a Waybar layout indicator. A self-contained Lua config
module for Hyprland 0.55+ — no plugin, no compiled component.

> Work in progress. Install and usage docs land in a later checkpoint.

## Development

```bash
make check   # stylua --check, luacheck, unit tests
make hooks   # enable the pre-commit hook (runs make check)
```

Requires (dev only): `luacheck`, `stylua` — `sudo pacman -S luacheck stylua`.
