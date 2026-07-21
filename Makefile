LUA      ?= lua
STYLUA   := $(shell [ -x bin/stylua ] && echo bin/stylua || echo stylua)
LUACHECK := $(shell [ -x bin/luacheck ] && echo bin/luacheck || echo luacheck)
SPECS    := $(wildcard spec/*_spec.lua)

HYPR_DIR    := $(if $(XDG_CONFIG_HOME),$(XDG_CONFIG_HOME),$(HOME)/.config)/hypr
MODULE_DEST := $(HYPR_DIR)/hypr-spellbook-swap
WAYBAR_BIN  := $(HOME)/.local/bin/hypr-spellbook-swap-waybar
FONT_DEST   := $(HOME)/.local/share/fonts/hypr-spellbook-swap-layouts.ttf

.PHONY: check fmt fmt-check lint test font verify verify-nix e2e hooks install uninstall

# Overridable so CI (or anyone testing against a non-system build) can point
# at an arbitrary Hyprland binary; default preserves today's behavior exactly
# (resolve "Hyprland" via PATH, i.e. the system package).
HYPRLAND ?= Hyprland
# Extra flags for the verify recipe; empty by default. verify-nix
HYPRLAND_FLAGS ?=

check: fmt-check lint test

fmt:
	$(STYLUA) .

fmt-check:
	$(STYLUA) --check .

lint:
	$(LUACHECK) .

test:
	@for f in $(SPECS); do echo "== $$f"; $(LUA) $$f || exit 1; done

font:
	cd font && ./build.sh

verify:
	$(HYPRLAND) $(HYPRLAND_FLAGS) --verify-config -c test/hyprland.lua

# Build upstream's current default-branch Hyprland via its own flake
# (bypassing flake.lock, which only pins a baseline) and run verify against
# it, all inside the official nixos/nix Docker image. Local Nix install is not required
# This is the same check the nightly CI job runs.
verify-nix:
	docker run --rm -v "$(CURDIR)":/workspace -w /workspace nixos/nix:latest sh -c '\
		git config --global --add safe.directory /workspace && \
		nix --extra-experimental-features "nix-command flakes" \
		    --option accept-flake-config true \
		    run --override-input hyprland github:hyprwm/Hyprland .#verify \
	'

e2e:
	./test/run-nested.sh

hooks:
	git config core.hooksPath .githooks
	@echo "pre-commit hook enabled (.githooks/pre-commit)"

# Copy (not symlink) the module into the Hyprland config dir so the live install
# is a stable snapshot: editing the repo does not change it until you re-run
# `make install`. install runs uninstall first and checks sources before removing.
install:
	@test -n "$(HOME)" || { echo "install: HOME is not set"; exit 1; }
	@test -d src || { echo "install: run from the repo root (missing src/)"; exit 1; }
	@test -f font/dist/hypr-spellbook-swap-layouts.ttf || { echo "install: font missing; run 'make font' first"; exit 1; }
	$(MAKE) uninstall
	mkdir -p "$(MODULE_DEST)" "$(HOME)/.local/bin" "$(HOME)/.local/share/fonts"
	cp src/*.lua "$(MODULE_DEST)/"
	cp scripts/waybar-layout.sh "$(WAYBAR_BIN)"
	chmod +x "$(WAYBAR_BIN)"
	cp font/dist/hypr-spellbook-swap-layouts.ttf "$(FONT_DEST)"
	fc-cache -f
	@echo "installed hypr-spellbook-swap (copied to $(MODULE_DEST))"

uninstall:
	@test -n "$(HOME)" || { echo "uninstall: HOME is not set"; exit 1; }
	@case "$(MODULE_DEST)" in */hypr-spellbook-swap) : ;; *) echo "uninstall: refusing unexpected path $(MODULE_DEST)"; exit 1 ;; esac
	rm -rf "$(MODULE_DEST)"
	rm -f "$(WAYBAR_BIN)" "$(FONT_DEST)"
	fc-cache -f
	@echo "uninstalled hypr-spellbook-swap"
