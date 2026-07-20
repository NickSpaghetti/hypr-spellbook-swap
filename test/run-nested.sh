#!/bin/bash
# Launch a nested (windowed) Hyprland using the isolated test config. When run
# inside an existing Wayland session, Hyprland runs windowed. Interact, then
# SUPER+SHIFT+Q to quit. Live session / config / state are untouched.
#
# SBS_E2E=1 tells test/hyprland.lua to register the custom Lua layouts, which
# only makes sense in a real (nested) instance -- `make verify` leaves it unset
# because hl.layout.register crashes Hyprland's --verify-config on 0.55.x.
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
mkdir -p "$repo/test/.state"
export SBS_E2E=1
exec Hyprland -c "$repo/test/hyprland.lua"
