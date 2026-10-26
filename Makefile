APP_NAME := Camera Tuner
BUILD_APP := build/$(APP_NAME).app
INSTALL_DIR ?= $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: all build run install uninstall reinstall icon clean help

all: build

build:
	./scripts/build.sh

run: build
	open "$(BUILD_APP)"

install: build
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALLED_APP)"
	@ditto "$(BUILD_APP)" "$(INSTALLED_APP)"
	@if [ -x "$(LSREGISTER)" ]; then "$(LSREGISTER)" -f "$(INSTALLED_APP)" >/dev/null 2>&1 || true; fi
	@echo "Installed: $(INSTALLED_APP)"

uninstall:
	@rm -rf "$(INSTALLED_APP)"
	@if [ -x "$(LSREGISTER)" ]; then "$(LSREGISTER)" -f "$(INSTALLED_APP)" >/dev/null 2>&1 || true; fi
	@echo "Removed: $(INSTALLED_APP)"

reinstall: uninstall install

icon:
	python3 scripts/make_icon.py

clean:
	rm -rf build

help:
	@echo "Camera Tuner"
	@echo ""
	@echo "  make build       Build the app into build/"
	@echo "  make run         Build and open the app"
	@echo "  make install     Install to ~/Applications (no sudo)"
	@echo "  make uninstall   Remove the installed app"
	@echo "  make reinstall   Uninstall, rebuild, and install"
	@echo "  make icon        Regenerate the app icon"
	@echo "  make clean       Remove build artifacts"
	@echo ""
	@echo "Install system-wide with:"
	@echo "  make install INSTALL_DIR=/Applications"
