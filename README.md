<div align="center">

<img src="docs/icon.png" width="128" alt="Spindle">

# Spindle

**A turntable that lives on your Mac desktop.**

It reads what you are playing in Music or Spotify and puts that record's cover
on the label. No account, no API key, no subscription.

<img src="docs/hero.jpg" alt="Spindle rendering a turntable on the desktop">

</div>

---

## What it is

A real-time 3-D scene rendered behind your desktop icons. The platter turns at
33⅓ rpm and the tonearm tracks inward as the track plays — pause, and it stops
where it is.

- **Reads Music and Spotify** over Apple Events. One permission prompt, then it
  just works, offline.
- **Three moods**, switchable from the menu bar.
- **Exports a still** at your display's resolution, if you would rather have a
  static wallpaper.
- **Lives in the menu bar.** No Dock icon, no window. Quit it and your desktop
  is exactly as it was.

Every surface — wood, lacquer, grooves, plaster, the app icon itself — is
generated from code at launch. Spindle ships no album artwork either: when
nothing is playing it draws its own abstract sleeve from a seed you choose.

## Install

Download the latest `.dmg` from [Releases](../../releases), open it, and drag
Spindle to Applications.

Or build it yourself — you need macOS 13 or later and the Xcode Command Line
Tools (`xcode-select --install`). There is no Xcode project and no package
dependencies.

```sh
git clone https://github.com/svviitzerland/spindle.git && cd spindle
make run
```

## The scenes

| Daylight | Lamplight | Overhead |
| --- | --- | --- |
| <img src="docs/daylight.jpg" alt=""> | <img src="docs/lamplight.jpg" alt=""> | <img src="docs/overhead.jpg" alt=""> |
| Raking morning light | One lamp, side two | Straight down on the deck |

## Using it

Everything is in the menu-bar menu (the disc icon):

| | |
| --- | --- |
| **Scene** | Switch mood |
| **Follow** | Whichever app is playing, or pin it to one, or **Standalone** to ignore music entirely |
| **Save Current Scene as Image…** | Render at your display's full resolution |
| **Settings…** | Frame rate, poll interval, the sleeve seed, open at login |

### Permissions and privacy

The first time Spindle reads a music app, macOS asks whether to allow it to
control **Music** or **Spotify**. That is how it learns the track and the cover.

If you say no, macOS will not ask again — allow it under **System Settings ›
Privacy & Security › Automation › Spindle**, then choose **Re-check
permissions** in Spindle's settings.

Spindle makes exactly one kind of network request: fetching the cover image
from the URL Spotify hands it. Music supplies artwork as raw bytes, so that
path never touches the network. Nothing is uploaded, ever.

## Command line

```sh
spindle render --scene lamplight --size 3840x2160 --out ~/Desktop/wall.png
spindle render --seed "side b" --progress 0.7
spindle scenes
spindle --help
```

`--progress` is where the stylus sits, from `0` (lead-in) to `1` (run-out).
`--seed` changes the generated sleeve; the same text always draws the same
record.

## How it works

**The wallpaper** is an ordinary `NSWindow` placed one level below the desktop
icons, present on every Space and ignoring the mouse. That is the whole trick —
see `Wallpaper/WallpaperWindow.swift`.

**The music** comes from Apple Events rather than the Spotify or Apple Music
web APIs. Those need an account, an OAuth redirect and a registered client;
Apple Events need one permission prompt and keep your listening history on your
machine. Spindle polls every couple of seconds, because both apps only post a
notification on *track change* — not on pause, resume or scrub.

**The look** comes from `Scene/Materials.swift`. Nothing in a real room has a
uniform roughness, so every material carries a roughness map and a normal map
built from a height field: orange peel on the paint, lathe marks on the
platter, fibre in the felt, grooves in the lacquer. The key lights are area
lights, because a point light carves hard-edged shadows no room has.

## Project layout

```
Sources/Spindle/
  App/          Entry point, menu bar, CLI subcommands
  Scene/        ScenePreset   pure data: camera, lights, surfaces, dressing
                TurntableScene  staging: room, light rig, camera
                Deck            the turntable, in real millimetres
                Props           mug, plant, books, headphones, lamp, shelf
                Materials       the PBR library
                Textures        per-pixel generators, normal-map builder
  NowPlaying/   Apple Events bridge, Music and Spotify providers, polling
  Wallpaper/    Desktop-level window, one per display
  Settings/     Preferences and the settings pane
  Support/      Logging, offscreen renderer, icon generator
```

## Adding a scene

Add a `ScenePreset` to `ScenePreset.all` and it appears in the menu, the
settings pane and `spindle render --scene` with no other changes.

Lighting a procedural scene takes a lot of small adjustments, so preset values
can be overridden from the shell while you work:

```sh
SPINDLE_HDR=0 SPINDLE_LIGHT=0.6 SPINDLE_EXPOSURE=-0.5 \
  .build/release/spindle render --scene my-scene --out /tmp/try.png
```

`SPINDLE_HDR=0` turns off tone mapping, which is the fastest way to see what is
clipping. The full list is in `Scene/SceneTuning.swift`. Once a value looks
right, move it into the preset and drop the variable.

> **One trap worth knowing:** SceneKit spreads an area light's intensity across
> its whole rectangle, so an area light needs an intensity roughly an order of
> magnitude larger than a spot or omni to match it. Intensities in
> `ScenePreset` are only comparable *within* a light kind.

## Releasing

Push a tag and the [release workflow](.github/workflows/release.yml) builds a
universal binary, packages a disk image and publishes it:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

Without signing secrets the app is signed ad-hoc — it runs, but Gatekeeper
warns on first open. To ship a signed, notarized build, set these repository
secrets:

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Developer ID Application certificate, base64 encoded |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Your 10-character team ID |
| `APPLE_APP_PASSWORD` | App-specific password for that Apple ID |

Each is optional. The workflow skips signing or notarization with a warning if
the matching secrets are missing, so a fork can cut releases without an Apple
Developer account.

## Make targets

| | |
| --- | --- |
| `make run` | Build, assemble the app, replace any running copy and launch |
| `make app` | Build the bundle without launching |
| `make dmg` | Package it as a disk image |
| `make stop` | Quit Spindle |
| `make render` | Write one frame as a PNG |
| `make check` | What CI runs |
| `make clean` | Remove `.build` and `dist` |

## Known limits

- Intel Macs are built but untested; releases are universal binaries.
- Materials and the environment map are procedural, not scanned. The scene aims
  at photographic and gets closer than flat shading does, but a real HDRI and
  scanned textures would get closer still.

## License

MIT. See [LICENSE](LICENSE).
