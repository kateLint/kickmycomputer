# Makefile for SmackYourComputer
# Synthesizes native Swift binary and bundles as a macOS App package.

APP_NAME = SmackYourComputer
APP_BUNDLE = $(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

.PHONY: all build run clean

all: build

build:
	@echo "========================================================="
	@echo "1. Assembling macOS App Bundle Directory Structure..."
	@echo "========================================================="
	mkdir -p $(MACOS)
	mkdir -p $(RESOURCES)/web
	
	@echo "\n========================================================="
	@echo "2. Compiling Native Swift Sensors and Interface Drivers..."
	@echo "========================================================="
	swiftc -sdk $$(xcrun --show-sdk-path --sdk macosx) \
		-framework Cocoa \
		-framework WebKit \
		-framework AVFoundation \
		InteractionEngine.swift main.swift \
		-o $(MACOS)/$(APP_NAME)
		
	@echo "\n========================================================="
	@echo "3. Copying Property Lists and Web Visual Assets..."
	@echo "========================================================="
	cp Info.plist $(CONTENTS)/
	cp icon.icns $(RESOURCES)/
	cp -r web/ $(RESOURCES)/
	
	@echo "\n========================================================="
	@echo "4. Deploying Self-Contained App directly to Desktop..."
	@echo "========================================================="
	rm -rf /Users/kerenlint/Desktop/$(APP_BUNDLE)
	cp -R $(APP_BUNDLE) /Users/kerenlint/Desktop/
	@echo "SUCCESS: Icon deployed to Desktop: /Users/kerenlint/Desktop/$(APP_BUNDLE)"
	@echo "========================================================="

run: build
	@echo "\nLaunching SmackYourComputer.app..."
	open /Users/kerenlint/Desktop/$(APP_BUNDLE)

clean:
	@echo "Cleaning compiled items and app packages..."
	rm -rf $(APP_BUNDLE)
	rm -rf /Users/kerenlint/Desktop/$(APP_BUNDLE)
	@echo "Clean completed."
