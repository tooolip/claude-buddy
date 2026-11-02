# Claude Buddy: build, bundle and run. See CLAUDE.md.
CONFIG ?= release
APP := build/ClaudeBuddy.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: all build app icon run stop install skin hooks unhooks hooks-status mem clean

all: app

build:
	swift build -c $(CONFIG)

icon: build/AppIcon.icns

build/AppIcon.icns: Skins/default/preview.png
	@mkdir -p build/AppIcon.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s Skins/default/preview.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s*2)) $$((s*2)) Skins/default/preview.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o $@

app: build icon
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/$(CONFIG)/ClaudeBuddy $(APP)/Contents/MacOS/ClaudeBuddy
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp build/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp -R Skins $(APP)/Contents/Resources/Skins
	codesign --force --sign - $(APP)

stop:
	-@pkill -x ClaudeBuddy; sleep 0.5

# Runs the freshly built copy from build/.
run: app stop
	open $(APP)

# Installs to ~/Applications (use this copy for "Open at login").
install: app stop
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/ClaudeBuddy.app
	cp -R $(APP) $(INSTALL_DIR)/ClaudeBuddy.app
	open $(INSTALL_DIR)/ClaudeBuddy.app

skin:
	swift Tools/make-skin.swift Skins/default

hooks:
	python3 scripts/hooks.py install

unhooks:
	python3 scripts/hooks.py uninstall

hooks-status:
	python3 scripts/hooks.py status

mem:
	@scripts/mem.sh

clean:
	rm -rf .build build
