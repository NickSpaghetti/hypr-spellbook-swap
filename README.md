# hypr-spellbook-swap

Cycle the focused Hyprland workspace between the tiling layouts [scrolling](https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/), [dwindle](https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/), [master](https://wiki.hypr.land/Configuring/Layouts/Master-Layout/), and your own [custom `lua:` layouts](https://wiki.hypr.land/Configuring/Layouts/Custom-Layouts/) on a keybind, with an optional notification and a Waybar layout indicator.

A self contained Lua config module for Hyprland 0.55+. No plugin and no compiled component. You install it with one `make` command and load it by name from your `hyprland.lua`. The icon font ships prebuilt, so there is nothing to compile.

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
* `~/.local/bin` on your PATH, so the installed Waybar exec resolves. Most setups already have this.

## Install

### 1. Clone and install

```bash
git clone https://github.com/NickSpaghetti/hypr-spellbook-swap.git
cd hypr-spellbook-swap
make install
```

`make install` copies a snapshot into place:

* the module into `~/.config/hypr/hypr-spellbook-swap`, so Hyprland can `require` it by name.
* the Waybar exec onto your PATH as `hypr-spellbook-swap-waybar`.
* the icon font into `~/.local/share/fonts`, then refreshes the font cache. Without the font the glyphs show up as tofu boxes.

Because it copies rather than symlinks, editing the repo does not change your live install until you re-run `make install`. That is deliberate, so a work in progress edit cannot break your running session. `make uninstall` removes all three.

### 2. Wire it into your hyprland.lua

Add this to `~/.config/hypr/hyprland.lua`:

```lua
local sb = require("hypr-spellbook-swap")
sb.setup({
    notify = true,
    notification_engine = "sway",
    sticky = true,
    cycle = { "scrolling", "dwindle", "lua:grid", "master" },
})
```

That binds `SUPER + L` to cycle through the layouts you list, and registers the bundled `grid` custom layout so `lua:grid` works. Remove any existing bind on the same keys first. Omit `cycle` to use the shipped default `{ "scrolling", "dwindle", "lua:grid" }`. See Configuration below for the rest.

### 3. Add the Waybar indicator

This step is optional. Add `"custom/hypr-spellbook-swap"` to a modules list in `~/.config/waybar/config.jsonc`, for example right after `"hyprland/workspaces"`. Then paste the module block from `waybar/custom-hypr-spellbook-swap.jsonc`:

```jsonc
"custom/hypr-spellbook-swap": {
    "exec": "hypr-spellbook-swap-waybar",
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

Pass options to `sb.setup{...}` in your `hyprland.lua`. `sb.setup` is where your config belongs, because `make install` overwrites the installed `layouts.lua` on every install. The shipped `src/layouts.lua` only supplies the defaults.

| Option | Default | Meaning |
| --- | --- | --- |
| `cycle` | `{ "scrolling", "dwindle", "lua:grid" }` | Rotation order. Use any built in layout name, or `"lua:<name>"` for a custom layout. |
| `default` | `"scrolling"` | Layout to switch to when the current one is not in `cycle`. |
| `icons` | glyphs for scrolling, dwindle, master, lua:grid | Map of layout key to the glyph shown in Waybar. Merged onto the defaults, so you only specify what you add or change. |
| `labels` | names for the same layouts | Map of layout key to a human name used in the tooltip and notification. Merged onto the defaults. |
| `notify` | `false` | Show a notification on switch. |
| `notification_engine` | `"hyprland"` | Use `"hyprland"` for the native overlay via `hl.notification`, or `"sway"` for `notify-send`. |
| `sticky` | `false` | Persist each workspace layout and re-apply it on setup so it survives `hyprctl reload`. |
| `mod` | `"SUPER"` | Modifier for the cycle bind. |
| `key` | `"L"` | Key for the cycle bind. |
| `waybar_signal` | `8` | Real time signal used to refresh Waybar via `pkill -RTMIN+N waybar`. Match the module `"signal"`. |
| `state_dir` | `~/.local/state/hypr-spellbook-swap` | Where sticky state is written. |
| `register` | the bundled `grid` provider | Custom Lua layout providers in the form `{ name = { recalculate = fn } }`. Defaults to the bundled providers so `lua:grid` works. Pass `{}` to register none, or your own table to replace. |
| `extra_layouts` | `{}` | Additional `lua:` layout names to accept as valid, for custom layouts registered outside this module. Built-in and plugin names need no declaration. |
| `hl` | the injected global `hl` | The Hyprland API table. Defaults to the `hl` global Hyprland injects. Override only for testing or advanced use. |
| `layouts` / `layouts_path` | `src/layouts.lua` | Pass a whole config table directly, or a path to load instead of the default. |

The bundled font already carries glyphs for `master` (U+E901) and `monocle` (U+E903), so adding either to `cycle` shows the right icon with no extra work. Custom layouts report their bare name at runtime, for example `grid`, but you reference them as `lua:grid` in `cycle`, `icons` and `labels`. The module resolves the two for you.

Icons and labels you set apply to both the notification and the Waybar indicator: `sb.setup` writes the effective config to `~/.local/state/hypr-spellbook-swap/waybar.lua`, and the separate Waybar process reads it (it cannot see your `sb.setup` opts directly). `layouts.lua` is only the shipped defaults.

Layout names are validated where the module can be authoritative. At load it drops any `lua:` layout in your `cycle` or `default` that is not registered (via `register` or declared in `extra_layouts`) and warns. Built-in and plugin names pass through, because Hyprland owns that namespace and gives no way to list it. As a runtime backstop it reads the layout back after each switch and warns if it did not actually take (Hyprland silently applies an unknown name as `dwindle`).

### Adding a layout to the rotation

Add it to `cycle` in your `sb.setup`. For a built in layout that the font already has a glyph for, for example `monocle`, just list it:

```lua
cycle = { "scrolling", "dwindle", "lua:grid", "master", "monocle" },
```

For a layout the font does not cover, also pass an `icons` and `labels` entry (they merge onto the defaults). For a brand new custom layout, add a provider to `custom_layouts.lua` (or pass `register`), then list it as `"lua:<name>"`.

## How it works

* `src/init.lua` is the `require` entry point. It self locates and returns the module, so `require("hypr-spellbook-swap")` works from wherever it is installed.
* `src/core.lua` is the pure layout logic: next in cycle, custom name resolution, state serialization and the Waybar state table. It has no `hl` and no I/O, and it is fully unit tested.
* `src/spellbook_swap.lua` is the adapter. It wires core to Hyprland's `hl` API for binds, events, workspace rules and notifications, and to on disk state. It decides nothing itself.
* `src/waybar.lua` and `src/waybar_emit.lua` are the Waybar edge. `waybar_emit.lua` runs as a separate process, so it reads the effective config `sb.setup` persists to `~/.local/state/hypr-spellbook-swap/waybar.lua` (falling back to the shipped defaults), then `core.waybar_state` builds a `{ text, tooltip }` table and `waybar.encode` turns it into the JSON it prints.

## Compatibility

Known good on Hyprland 0.55.4 and 0.56.0. This module rides on Hyprland's Lua `hl` API, which is new as of 0.55 and still changing between releases. An upgrade can rename or change a call it depends on, and if that happens `SUPER + L`, the Waybar indicator, or notifications can stop working. The `hl` surface it uses:

* `hl.bind` and `hl.on`, for the keybind and the "workspace.active" / "monitor.focused" refresh events
* `hl.layout.register(name, provider)`, for custom layouts
* `hl.get_active_workspace()` and its `.id` and `.tiled_layout` fields
* `hl.workspace_rule({ workspace = "<id>", layout = "<name>" })`, to switch a workspace's layout at runtime
* `hl.exec_cmd` and `hl.notification.create`

After upgrading Hyprland, re-verify. The unit tests run against a fake `hl`, so they cannot catch an API change. Do a real check:

1. `make verify`, to confirm the config still loads.
2. A live smoke test: press `SUPER + L` and watch `hyprctl activeworkspace -j | jq .tiledLayout` change, run `hypr-spellbook-swap-waybar` by hand, and confirm a notification fires.

## Development

```bash
make check      # the gate: stylua --check ., luacheck ., then each spec/*_spec.lua
make hooks      # enable the pre-commit hook, it runs make check on every commit
make verify     # validate test/hyprland.lua through real Hyprland with no compositor
make e2e        # nested Hyprland using test/hyprland.lua, press SUPER+SHIFT+Q to quit
make font       # rebuild font/dist/hypr-spellbook-swap-layouts.ttf from font/icons/*.svg, needs fontforge
make install    # copy the module into ~/.config/hypr, the waybar exec onto PATH, and the font
make uninstall  # remove everything make install put in place
```

Dev tools install with `sudo pacman -S luacheck stylua`, plus `fontforge` only if you edit the SVGs. Tests and `make verify` run against the repo, not the install, so you develop against the repo and re-run `make install` when you want the live copy updated. The tests use a fake `hl` and a throwaway `state_dir` under `test/`, so nothing touches your live config or session.

A note on `make verify`. Calling `hl.layout.register` crashes `Hyprland --verify-config` on 0.55.x, so `test/hyprland.lua` registers custom layouts only in the nested run under `make e2e`, not under `make verify`. This is fixed upstream in Hyprland 0.56.0.

## Repo layout

```
src/       init.lua, core.lua, spellbook_swap.lua, layouts.lua, custom_layouts.lua, waybar.lua, waybar_emit.lua
spec/      unit tests for core, glue and waybar, plus a tiny zero dep harness
scripts/   waybar-layout.sh, the Waybar exec
waybar/    custom-hypr-spellbook-swap.jsonc module + style-snippet.css to paste into your Waybar config
font/      icon SVGs, build.sh, and the prebuilt dist/hypr-spellbook-swap-layouts.ttf
test/      isolated hyprland.lua and run-nested.sh for verify and e2e
```
