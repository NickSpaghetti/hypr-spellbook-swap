LUA      ?= lua
STYLUA   := $(shell [ -x bin/stylua ] && echo bin/stylua || echo stylua)
LUACHECK := $(shell [ -x bin/luacheck ] && echo bin/luacheck || echo luacheck)
SPECS    := $(wildcard spec/*_spec.lua)

HYPR_DIR    := $(if $(XDG_CONFIG_HOME),$(XDG_CONFIG_HOME),$(HOME)/.config)/hypr
MODULE_DEST := $(HYPR_DIR)/hypr-spellbook-swap
WAYBAR_BIN  := $(HOME)/.local/bin/hypr-spellbook-swap-waybar
FONT_DEST   := $(HOME)/.local/share/fonts/hypr-spellbook-swap-layouts.ttf
STATE_DIR   := $(HOME)/.local/state/hypr-spellbook-swap

.DEFAULT_GOAL := help

.PHONY: help check fmt fmt-check lint test font verify verify-nix e2e hooks install uninstall reset-state remove-installed-files

# Overridable so CI (or anyone testing against a non-system build) can point
# at an arbitrary Hyprland binary; default preserves today's behavior exactly
# (resolve "Hyprland" via PATH, i.e. the system package).
HYPRLAND ?= Hyprland
# Extra flags for the verify recipe; empty by default. verify-nix
HYPRLAND_FLAGS ?=

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

check: ## Run stylua --check, luacheck, and unit tests
check: fmt-check lint test

fmt: ## Format Lua with stylua
	$(STYLUA) .

fmt-check: ## Check Lua formatting
	$(STYLUA) --check .

lint: ## Run luacheck
	$(LUACHECK) .

test: ## Run the unit tests
	@for f in $(SPECS); do echo "== $$f"; $(LUA) $$f || exit 1; done

font: ## Rebuild the icon font from SVGs
	cd font && ./build.sh

verify: ## Validate test/hyprland.lua through Hyprland
	$(HYPRLAND) $(HYPRLAND_FLAGS) --verify-config -c test/hyprland.lua

# Build upstream's current default-branch Hyprland via its own flake
# (bypassing flake.lock, which only pins a baseline) and run verify against
# it, all inside the official nixos/nix Docker image. Local Nix install is not required
# This is the same check the nightly CI job runs, so keep the container
# invocation below in sync with .github/workflows/nightly.yml.
#
# GH_TOKEN is optional here (CI always sets it, from github.token): Nix's
# github: fetcher calls api.github.com once per flake input, and 60/hr
# unauthenticated is easy to exhaust. Export GH_TOKEN=$$(gh auth token) to get
# the 1000/hr limit; leaving it unset just falls back to anonymous fetches.
#
# The `: > /.socket2.sock` line works around hyprwm/Hyprland#15624, which
# segfaults `Hyprland --verify-config`: postConfigReload() guards its socket2
# post with `if (IPC::Socket2::sock())`, but sock() is a function-local static
# that always constructs, so the guard never fails and evaluating it builds the
# socket. Under --verify-config the compositor ctor returns early, leaving
# m_instancePath empty and m_wlEventLoop null, so CUnixImpl binds to
# "/.socket2.sock" (succeeds, since we are root in the container) and then
# dereferences the null event loop. Pre-creating the path makes bind() fail
# EADDRINUSE, taking an early-return the ctor already has. Expect an ERR line
# about failing to bind Socket 2 -- that is the workaround, not a regression.
# Delete the line once upstream is fixed.
#
# Comments cannot live inside the sh -c below: make joins the backslash
# continuations into one line, so a # would comment out everything after it.
# (This is why the notes above are here rather than beside each command.)
verify-nix: ## Verify against upstream Hyprland in Docker
	docker run --rm -e GH_TOKEN -v "$(CURDIR)":/workspace -w /workspace nixos/nix:latest sh -c '\
		if [ -n "$$GH_TOKEN" ]; then \
			mkdir -p /etc/nix && \
			printf "access-tokens = github.com=%s\n" "$$GH_TOKEN" >> /etc/nix/nix.conf; \
		fi; \
		: > /.socket2.sock; \
		git config --global --add safe.directory /workspace && \
		nix --extra-experimental-features "nix-command flakes" \
		    --option accept-flake-config true \
		    run --override-input hyprland github:hyprwm/Hyprland .#verify \
	'

e2e: ## Nested Hyprland session (SUPER+SHIFT+Q to quit)
	./test/run-nested.sh

hooks: ## Configure this repository to use .githooks
	git config core.hooksPath .githooks
	@echo "pre-commit hook enabled (.githooks). Bypass a single commit with --no-verify."
	@echo "disable with: git config --unset core.hooksPath"

# Copy (not symlink) the module into the Hyprland config dir so the live install
# is a stable snapshot: editing the repo does not change it until you re-run
# `make install`. install overwrites the copied files in place so Hyprland's
# config watcher never sees a missing `require("hypr-spellbook-swap")`. Sticky
# state is left alone.
remove-installed-files:
	@test -n "$(HOME)" || { echo "remove-installed-files: HOME is not set"; exit 1; }
	@case "$(MODULE_DEST)" in */hypr-spellbook-swap) : ;; *) echo "remove-installed-files: refusing unexpected path $(MODULE_DEST)"; exit 1 ;; esac
	rm -rf "$(MODULE_DEST)"
	rm -f "$(WAYBAR_BIN)" "$(FONT_DEST)"
	fc-cache -f

reset-state: ## Delete sticky state under ~/.local/state/hypr-spellbook-swap
	@test -n "$(HOME)" || { echo "reset-state: HOME is not set"; exit 1; }
	@case "$(STATE_DIR)" in */hypr-spellbook-swap) : ;; *) echo "reset-state: refusing unexpected path $(STATE_DIR)"; exit 1 ;; esac
	rm -rf "$(STATE_DIR)"
	@echo "removed sticky state $(STATE_DIR)"

install: ## Install the module, Waybar exec, and font
	@test -n "$(HOME)" || { echo "install: HOME is not set"; exit 1; }
	@test -d src || { echo "install: run from the repo root (missing src/)"; exit 1; }
	@test -f font/dist/hypr-spellbook-swap-layouts.ttf || { echo "install: font missing; run 'make font' first"; exit 1; }
	mkdir -p "$(MODULE_DEST)" "$(HOME)/.local/bin" "$(HOME)/.local/share/fonts"
	cp src/*.lua "$(MODULE_DEST)/"
	cp scripts/waybar-layout.sh "$(WAYBAR_BIN)"
	chmod +x "$(WAYBAR_BIN)"
	cp font/dist/hypr-spellbook-swap-layouts.ttf "$(FONT_DEST)"
	fc-cache -f
	@echo "installed hypr-spellbook-swap (copied to $(MODULE_DEST))"

uninstall: ## Remove the install and sticky state
uninstall: remove-installed-files reset-state
	@echo "uninstalled hypr-spellbook-swap"
