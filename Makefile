LUA      ?= lua
STYLUA   := $(shell [ -x bin/stylua ] && echo bin/stylua || echo stylua)
LUACHECK := $(shell [ -x bin/luacheck ] && echo bin/luacheck || echo luacheck)
SPECS    := $(wildcard spec/*_spec.lua)

.PHONY: check fmt fmt-check lint test font verify e2e hooks install-font uninstall-font

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
	Hyprland --verify-config -c test/hyprland.lua

e2e:
	./test/run-nested.sh

hooks:
	git config core.hooksPath .githooks
	@echo "pre-commit hook enabled (.githooks/pre-commit)"

install-font:
	mkdir -p "$(HOME)/.local/share/fonts"
	ln -sf "$(CURDIR)/font/dist/hypr-spellbook-swap-layouts.ttf" "$(HOME)/.local/share/fonts/hypr-spellbook-swap-layouts.ttf"
	fc-cache -f
	@echo "linked into ~/.local/share/fonts; run make uninstall-font to remove"

uninstall-font:
	rm -f "$(HOME)/.local/share/fonts/hypr-spellbook-swap-layouts.ttf"
	fc-cache -f
	@echo "removed the font symlink"
