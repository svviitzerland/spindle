# Spindle — notes for Claude

A macOS menu-bar app that renders a 3-D turntable as the desktop wallpaper and
shows the cover of whatever is playing in Music or Spotify.

Swift 5.9+, SwiftPM only. No Xcode project, no dependencies.

## Commands

```sh
make run      # build, assemble dist/Spindle.app, relaunch
make check    # what CI runs: build + CLI + bundle + codesign verify
make dmg      # package a disk image
make stop     # quit a running copy
```

Render a frame instead of taking over the desktop — this is the fastest way to
see a scene change:

```sh
.build/release/spindle render --scene daylight --size 1100x619 --out /tmp/a.png
```

Scene ids: `daylight`, `gallery`, `sage`, `clay`, `conservatory`, `dusk`,
`lamplight`, `overhead`.

Palettes can only be judged against each other, so render them all at once:

```sh
.build/release/spindle contact --out /tmp/sheet.png
```

## Where things live

- `Scene/Palette.swift` — named colour schemes. Surfaces are grouped here so
  a palette can be judged as a palette rather than as thirty loose numbers.
- `Scene/ScenePreset.swift` — the shape of a scene. Nearly every field has a
  default and anything palette-dependent is derived, so a preset states only
  what makes it different.
- `Scene/Presets.swift` — the scenes themselves. Add one to `all` and it
  appears in the menu, the settings pane and `--scene` with no other change.
- `Scene/Materials.swift` — the PBR library. Every material carries a roughness
  and normal map; never a flat scalar.
- `Scene/Deck.swift` — the turntable, in real millimetres.
- `Wallpaper/WallpaperWindow.swift` — the desktop-level window.

Tuning hooks (`SPINDLE_HDR=0`, `SPINDLE_LIGHT`, `SPINDLE_EXPOSURE`) are in
`Scene/SceneTuning.swift`. Bake good values into the preset afterwards.

Two traps worth knowing before you touch lighting:

- **Light intensities are not comparable across kinds.** SceneKit spreads an
  area light over its whole rectangle, so an area light needs a figure roughly
  an order of magnitude larger than a spot or omni. An omni at 11 will bury an
  area light at 760.
- **`fStop` is a blur strength, not an aperture.** SceneKit's defocus is far
  weaker than the optics the number describes; anything above about 1.5 looks
  like everything is in focus.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org). Keep the
subject imperative and under ~72 characters.

```
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `style`, `test`, `build`,
`ci`, `chore`.

Scope is the area touched — `scene`, `deck`, `materials`, `wallpaper`,
`nowplaying`, `settings`, `cli`, `icon`, `release`.

```
feat(scene): add the overhead camera preset
fix(nowplaying): stop launching Spotify when it is closed
perf(textures): cache generated normal maps between rebuilds
docs: explain the area-light intensity scale
```

Breaking changes get a `!` before the colon and a `BREAKING CHANGE:` footer.

Release tags are `vX.Y.Z` and trigger `.github/workflows/release.yml`.
