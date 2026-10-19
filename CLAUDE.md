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

Scene ids: `daylight`, `lamplight`, `overhead`.

## Where things live

- `Scene/ScenePreset.swift` — pure data: camera, lights, surfaces, dressing.
  Add a preset to `all` and it appears everywhere with no other change.
- `Scene/Materials.swift` — the PBR library. Every material carries a roughness
  and normal map; never a flat scalar.
- `Scene/Deck.swift` — the turntable, in real millimetres.
- `Wallpaper/WallpaperWindow.swift` — the desktop-level window.

Tuning hooks (`SPINDLE_HDR=0`, `SPINDLE_LIGHT`, `SPINDLE_EXPOSURE`) are in
`Scene/SceneTuning.swift`. Bake good values into the preset afterwards.

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
