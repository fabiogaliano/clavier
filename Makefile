PROJECT := clavier.xcodeproj
SCHEME  := clavier
DERIVED := build
APP     := $(DERIVED)/Build/Products/Release/clavier.app
DEST    := /Applications/clavier.app

.PHONY: help build install run test clean

help:
	@echo "Targets:"
	@echo "  make build     Build Release .app into $(DERIVED)/"
	@echo "  make install   Build + copy to $(DEST) + relaunch"
	@echo "  make run       Open installed app"
	@echo "  make test      Run clavierTests"
	@echo "  make clean     Remove $(DERIVED)/"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration Release -derivedDataPath $(DERIVED) -quiet build

install: build
	-killall clavier 2>/dev/null || true
	rm -rf $(DEST)
	cp -R $(APP) $(DEST)
	open $(DEST)

run:
	open $(DEST)

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration Debug \
	  -destination 'platform=macOS,arch=arm64' \
	  test

clean:
	rm -rf $(DERIVED)
