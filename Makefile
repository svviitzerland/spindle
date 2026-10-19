# Spindle — a turntable on your desktop.

CONFIG ?= release
APP    := dist/Spindle.app

.PHONY: all build universal app dmg run stop render icon check clean

all: app

## Build the executable for this machine.
build:
	swift build -c $(CONFIG)

## Build for Apple Silicon and Intel in one binary. Used by releases.
universal:
	swift build -c $(CONFIG) --arch arm64 --arch x86_64

## Assemble dist/Spindle.app. Pass VERSION=1.2.3 to stamp the Info.plist.
app: build
	CONFIG=$(CONFIG) ./scripts/bundle.sh

## Rebuild, replace any running copy, and launch.
run: stop app
	open $(APP)

## Quit a running Spindle without touching the build.
stop:
	-@pkill -x spindle 2>/dev/null || true

## Package the app as a disk image.
dmg: app
	./scripts/dmg.sh

## Render one frame to a PNG you can set as a static wallpaper.
##   make render SCENE=lamplight SIZE=3840x2160 OUT=~/Desktop/spindle.png
SCENE ?= daylight
SIZE  ?= 2560x1440
OUT   ?= dist/spindle-$(SCENE).png
render: build
	.build/$(CONFIG)/spindle render --scene $(SCENE) --size $(SIZE) --out $(OUT)

icon: build
	.build/$(CONFIG)/spindle icon --out dist/icon

## What CI runs: build, exercise the CLI, assemble and verify the bundle.
check: build
	.build/$(CONFIG)/spindle --help > /dev/null
	.build/$(CONFIG)/spindle scenes
	$(MAKE) app
	codesign --verify --strict $(APP)

clean:
	rm -rf .build dist
