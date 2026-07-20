# hypr-spellbook-swap

Cycle the focused Hyprland workspace between the tiling layouts [scrolling](https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/), [dwindle](https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/), and your own [custom `lua:` layouts](https://wiki.hypr.land/Configuring/Layouts/Custom-Layouts/) on a keybind, with an optional notification and a Waybar layout indicator.

A self contained Lua config module for Hyprland 0.55+. No plugin and no compiled component. You load one file from your `hyprland.lua`. The icon font ships prebuilt, so there is nothing to compile to use it.

## Features

* One keybind cycles the layout on the focused workspace. The default is `SUPER + L` and it wraps through a list you configure.
* A Waybar custom module shows a per layout glyph and a `Layout: <name>` tooltip. It refreshes on workspace and monitor changes with no polling.
* An optional notification on each switch, either the native Hyprland overlay or `notify-send`.
* Optional sticky state. Each workspace remembers its layout and gets it back after `hyprctl reload`.
* A pure, tested core. All of the layout logic lives in `src/core.lua` with unit tests, and the rest is thin glue.

## Requirements

* Hyprland 0.55+ using the Lua config at `~/.config/hypr/hyprland.lua`.
* `jq`, used by the Waybar exec script.
* A Waybar setup if you want the indicator.

Replace `/path/to/hypr-spellbook-swap` below with wherever you cloned the repo. Hyprland loads the module by absolute path because the repo is not on Hyprland's require path, so the paths have to be absolute.

## Install

### 1. Install the icon font

Without it the glyphs show up as tofu boxes. The `.ttf` is committed, so you do not need FontForge. From the repo root:

```bash
make install-font
```

That symlinks the font into `~/.local/share/fonts` and refreshes the font cache. The font is named `hypr-spellbook-swap-layouts`, not anything that looks official to Hyprland. To remove it later, run `make uninstall-font`. Because it is a symlink and not a copy, deleting the repo also takes the font data with it.

Confirm it registered with `fc-list | grep hypr-spellbook-swap-layouts`.

### 2. Wire it into your hyprland.lua

Add this to `~/.config/hypr/hyprland.lua`:

```lua
local sb = dofile("/path/to/hypr-spellbook-swap/src/spellbook_swap.lua")
sb.setup({
    -- register the bundled example custom layouts, this gives you "lua:grid"
    register = dofile("/path/to/hypr-spellbook-swap/src/custom_layouts.lua"),
})
```

That binds `SUPER + L` to cycle the layout. Remove any existing bind on the same keys first. See Configuration below to change the keybind, the rotation, notifications and more.

### 3. Add the Waybar indicator

This step is optional. Add `"custom/hypr-layout"` to a modules list in `~/.config/waybar/config.jsonc`, for example right after `"hyprland/workspaces"`. Then paste the module block from `waybar/custom-hypr-layout.jsonc` and fix the exec path:

```jsonc
"custom/hypr-layout": {
    "exec": "/path/to/hypr-spellbook-swap/scripts/waybar-layout.sh",
    "return-type": "json",
    "signal": 8,
    "tooltip": true,
    "format": "{}"
}
```

Then merge `waybar/style-snippet.css` into your `style.css`. It prepends `"hypr-spellbook-swap-layouts"` to the module font stack so the glyphs resolve.

### 4. Reload

```bash
hyprctl reload
```

Then restart Waybar.

## Configuration

Pass options to `sb.setup{...}`, or edit `src/layouts.lua`, which holds the defaults. An option you pass to setup always wins over the `layouts.lua` value.

| Option | Default | Meaning |
| --- | --- | --- |
| `cycle` | `{ "scrolling", "dwindle", "lua:grid" }` | Rotation order. Use any built in layout name, or `"lua:<name>"` for a custom layout. |
| `default` | `"scrolling"` | Layout to switch to when the current one is not in `cycle`. |
| `icons` | glyphs for the three defaults | Map of layout key to the glyph shown in Waybar. |
| `labels` | names for the three defaults | Map of layout key to a human name used in the tooltip and notification. |
| `notify` | `false` | Show a notification on switch. |
| `notification_engine` | `"hyprland"` | Use `"hyprland"` for the native overlay via `hl.notification`, or `"sway"` for `notify-send`. |
| `sticky` | `false` | Persist each workspace layout and re-apply it on setup so it survives `hyprctl reload`. |
| `mod` | `"SUPER"` | Modifier for the cycle bind. |
| `key` | `"TAB"` | Key for the cycle bind. |
| `waybar_signal` | `8` | Real time signal used to refresh Waybar via `pkill -RTMIN+N waybar`. Match the module `"signal"`. |
| `state_dir` | `~/.local/state/hypr-spellbook-swap` | Where sticky state is written. |
| `register` | `{}` | Custom Lua layout providers in the form `{ name = { recalculate = fn } }`. They are registered with `hl.layout.register`. |
| `layouts` / `layouts_path` | `src/layouts.lua` | Pass a config table directly, or a path to load instead of the default. |

Custom layouts report their bare name at runtime, for example `grid`, but you reference them as `lua:grid` in `cycle`, `icons` and `labels`. The module resolves the two for you.

### Adding a layout to the rotation

This is a data only change. You never touch `src/core.lua` or `src/spellbook_swap.lua`.

For a built in layout such as `master`, add `"master"` to `cycle` and give it an `icons` and `labels` entry.

For a new custom layout such as `spiral`, add a `spiral = { recalculate = function(ctx) ... end }` provider to `src/custom_layouts.lua`, then add `"lua:spiral"` to `cycle` with its `icons` and `labels` entry.

## How it works

* `src/core.lua` is the pure layout logic: next in cycle, custom name resolution, state serialization and the Waybar state table. It has no `hl` and no I/O, and it is fully unit tested.
* `src/spellbook_swap.lua` is the adapter. It wires core to Hyprland's `hl` API for binds, events, `exec_cmd` and notifications, and to on disk state. It decides nothing itself.
* `src/waybar.lua` and `src/waybar_emit.lua` are the Waybar edge. Core produces a `{ text, tooltip }` table, `waybar.encode` turns it into JSON, and `waybar_emit.lua` prints it for the exec script.

## Development

```bash
make check          # the gate: stylua --check ., luacheck ., then each spec/*_spec.lua
make hooks          # enable the pre-commit hook, it runs make check on every commit
make verify         # validate test/hyprland.lua through real Hyprland with no compositor
make e2e            # nested Hyprland using test/hyprland.lua, press SUPER+SHIFT+Q to quit
make font           # rebuild font/dist/hypr-spellbook-swap-layouts.ttf from font/icons/*.svg, needs fontforge
make install-font   # symlink the font into ~/.local/share/fonts and refresh the cache
make uninstall-font # remove that symlink and refresh the cache
```

Dev tools install with `sudo pacman -S luacheck stylua`, plus `fontforge` only if you edit the SVGs. The tests use a fake `hl` and a throwaway `state_dir` under `test/`, so nothing touches your live config or session.

A note on `make verify`. Calling `hl.layout.register` crashes `Hyprland --verify-config` on 0.55.x, so `test/hyprland.lua` registers custom layouts only in the nested run under `make e2e`, not under `make verify`. This is fixed upstream in Hyprland 0.56.0.

## Repo layout

```
src/       core.lua, spellbook_swap.lua, layouts.lua, custom_layouts.lua, waybar.lua, waybar_emit.lua
spec/      unit tests for core, glue and waybar, plus a tiny zero dep harness
scripts/   waybar-layout.sh, the Waybar exec
waybar/    module and style snippets to paste into your Waybar config
font/      icon SVGs, build.sh, and the prebuilt dist/hypr-spellbook-swap-layouts.ttf
test/      isolated hyprland.lua and run-nested.sh for verify and e2e
```
