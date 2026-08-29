#!/bin/bash
# Waybar on-click: run the same cycle() as SUPER+L inside the compositor Lua VM.
# `hyprctl eval` executes in the live config state, so sticky, notify, and the
# Waybar signal all fire. Do not re-implement next-layout out here.
set -euo pipefail
exec hyprctl eval 'require("hypr-spellbook-swap").cycle()'
