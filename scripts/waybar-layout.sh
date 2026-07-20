#!/bin/bash
# Waybar custom-module exec: print the active workspace's layout as JSON.
# Self-locating -- resolves the repo from this script's own path.
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
tiled_layout="$(hyprctl activeworkspace -j | jq -r '.tiledLayout')"
exec lua "$repo/src/waybar_emit.lua" "$tiled_layout"
