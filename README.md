<div align="center">

<img src="docs/icon.png" width="120" alt="Spindle">

# Spindle

**A turntable for your Mac desktop.**

Play something in Music or Spotify and its cover drops onto the record.
The platter spins while the track plays, and stops when you pause.

<img src="docs/hero.jpg" alt="Spindle running on the desktop">

</div>

## Features

* Your album art, on a spinning record, behind your desktop icons
* Three scenes to pick from
* Coloured pressings, and you can add your own
* Can match your lock screen too
* Lives in the menu bar and stays out of the way
* Free and open source

## Scenes

| Daylight | Lamplight | Overhead |
| :-: | :-: | :-: |
| <img src="docs/daylight.jpg" alt=""> | <img src="docs/lamplight.jpg" alt=""> | <img src="docs/overhead.jpg" alt=""> |
| Morning light through a window | One lamp, late at night | Straight down on the deck |

## Install

Download the latest `.dmg` from [Releases](../../releases), open it, and drag
Spindle to your Applications folder.

The first time it runs, macOS asks for permission to read Music or Spotify.
Allow it, and your cover art shows up. Everything stays on your Mac.

## Build from source

You need macOS 13 or later and the Xcode Command Line Tools
(`xcode-select --install`).

```sh
git clone https://github.com/svviitzerland/spindle.git
cd spindle
make run
```

`make run` builds the app and launches it. `make stop` quits it.

## License

MIT. See [LICENSE](LICENSE).
