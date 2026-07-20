#!/usr/bin/env bash
# Build hypr-spellbook-swap-layouts.ttf + .otf from the SVGs in ./icons
# Requires: fontforge  (sudo pacman -S fontforge  /  apt install fontforge)
# Run:  ./build.sh   ->  outputs dist/hypr-spellbook-swap-layouts.ttf and .otf
set -euo pipefail
mkdir -p dist
fontforge -lang=py -script - <<'PY'
import fontforge, glob, os, re
f = fontforge.font()
f.familyname = "hypr-spellbook-swap-layouts"
f.fontname   = "hypr-spellbook-swap-layouts"
f.fullname   = "hypr-spellbook-swap-layouts"
f.encoding   = "UnicodeFull"
f.em         = 1000
f.ascent, f.descent = 800, 200
for path in sorted(glob.glob("icons/*.svg")):
    cp = int(re.match(r"([0-9a-fA-F]{4})", os.path.basename(path)).group(1), 16)
    g = f.createChar(cp)
    g.importOutlines(path)
    g.stroke("circular", 60)
    g.removeOverlap()
    g.correctDirection()
    g.width = 1000
f.generate("dist/hypr-spellbook-swap-layouts.ttf")
f.generate("dist/hypr-spellbook-swap-layouts.otf")
print("wrote dist/hypr-spellbook-swap-layouts.ttf and .otf")
PY
