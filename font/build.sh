#!/usr/bin/env bash
# Build hyprland-layouts.ttf + .otf from the SVGs in ./icons
# Requires: fontforge  (sudo pacman -S fontforge  /  apt install fontforge)
# Run:  ./build.sh   ->  outputs dist/hyprland-layouts.ttf and .otf
set -euo pipefail
mkdir -p dist
fontforge -lang=py -script - <<'PY'
import fontforge, glob, os, re
f = fontforge.font()
f.familyname = "Hyprland Layouts"
f.fontname   = "HyprlandLayouts"
f.fullname   = "Hyprland Layouts"
f.encoding   = "UnicodeFull"
f.em         = 1000
f.ascent, f.descent = 800, 200
for path in sorted(glob.glob("icons/*.svg")):
    cp = int(re.match(r"([0-9a-fA-F]{4})", os.path.basename(path)).group(1), 16)
    g = f.createChar(cp)
    g.importOutlines(path)              # imports the stroked SVG
    g.stroke("circular", 60)            # expand strokes -> filled outlines (60/1000em ~ the 1px lines)
    g.removeOverlap()
    g.correctDirection()
    g.width = 1000
f.generate("dist/hyprland-layouts.ttf")
f.generate("dist/hyprland-layouts.otf")
print("wrote dist/hyprland-layouts.ttf and .otf")
PY
