#!/bin/bash
# Waybar custom-module exec: print the active workspace's layout as JSON.
# Runs the installed module that `make install` copies into the Hyprland config dir.
set -euo pipefail
module="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hypr-spellbook-swap"
tiled_layout="$(hyprctl activeworkspace -j | jq -r '.tiledLayout')"
exec lua "$module/waybar_emit.lua" "$tiled_layout"
