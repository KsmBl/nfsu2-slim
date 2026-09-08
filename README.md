# NFS Underground 2 — 120 MB build

Shrinks a stock *Need for Speed: Underground 2* PC install from **1.8 GB** to a
**~117 MB archive** that fits a 120 MB SD card, and runs it from RAM.

The key idea: the game never had to *run* from the card, only *fit* on it.
The card carries a compressed archive; the game is extracted to `/dev/shm`
(tmpfs) at launch and played from there.

| | Size |
|---|---:|
| Stock install | 1843 MiB |
| After `strip-nfsu2.sh` | 417 MiB |
| `nfsu2.tar.xz` (`xz -9e`) | **117 MiB** |
| SD card usable | 119.3 MiB |

Compression is this effective because most of the bulk is EA's own
*uncompressed* bundle formats — `STREAML4RA.BUN` alone goes 113 → 32 MiB.

## Usage

```sh
./strip-nfsu2.sh /path/to/install    # shrink a stock install (idempotent)
./build-archive.sh nfsu2.tar.xz      # pack it
./play-nfsu2.sh    nfsu2.tar.xz      # extract to RAM and launch under Wine
```

`play-nfsu2.sh` needs no root — `/dev/shm` is already tmpfs. It checks free RAM
before extracting (~4× archive size) and clears the RAM copy on exit.
Measured extract: **2 seconds** for 258 MiB.

## What you get

* **14 playable cars** — 350Z (Rachel's) plus 240SX, Celica, Civic, Corolla,
  Corsa, Focus, IS300, Miata, Peugeot 206/106, Sentra, Supra, Tiburon
* **All 24 wheel brands**
* **One city region** — L4RA, the City Core you start in, with 60 of the
  game's 105 events and its full AI routing
* All 15 traffic cars, full audio, working races and minimap markers

## What you lose

No cutscenes or intro videos, no music or speech, no vinyls, no body-kit
parts (spoilers/roofs/mirrors), no minimap background art, and 7 of 8 city
regions — so 45 events outside the City Core cannot load.

## Method

Two rules, learned the hard way:

1. **Empty, don't delete.** Assets are truncated to 0 bytes so every filename
   still resolves. Files are deleted only when `SPEED2.EXE` contains no
   reference to them at all (`Support/`, the uninstaller).
2. **Prefer EA's own empty form.** Where the game ships an empty version of a
   thing, copy that rather than inventing one:
   * `MOVIES/blank.vp6` — a valid 1s VP6 stream, used for all 28 videos
   * `SUBTITLES/Scene20` — an 8-byte empty subtitle table
   * `ROUTESL4RH/RoutesAll.bin` — an 8-byte empty route chunk
   * 28 of the stock `VINYLS.BIN` are already 0 bytes

### `SPEED2.EXE` reaches data two ways

This distinction predicted almost every success and failure:

| Pattern paths — safe to empty | Literal paths — handle with care |
|---|---|
| `CARS\%s\GEOMETRY.BIN` | `GLOBAL\GLOBALB.BUN` |
| `CARS\WHEELS\GEOMETRY_%s.BIN` | `Global\InGameCommon.bun` |
| `TRACKS\STREAM%s.BUN` | `FRONTEND\PLATFORMS\SHOWROOM.BIN` |
| `TRACKS\TRACKMAP%d.bin` | `SOUND\**\*.abk` (named individually) |
| `%sMOVIES\%s%s` | |

Pattern paths resolve per-item at use time — an empty file there costs you one
car or one map. Literal paths are opened by name during init, and an empty file
fails at *parse*, killing the process before a window appears.

The exception: body-part geometry (`CARS\ROOF\GEOMETRY.BIN` and friends) is
literal-named yet empties cleanly. Treat the split as a strong heuristic, not
a law.

### `SDATA/sdat.viv`

Music and speech live inside a `BIG4` archive, so they can't be deleted as
files. `strip-nfsu2.sh` rebuilds it: all 10 entries keep their names, order and
descriptor content, while the three bulk payloads (`MusicSFx.mus`,
`UG2_Speech_GR.big`, `nisaudio.big`) are emptied. 258,599,488 → 15,264 bytes.

## Things that do not work

Tested and reverted — don't repeat these:

* **Sharing one car model across cars.** Geometry files carry a per-car part
  table (`CIVIC_BASE_A`, ~600 entries). Point another car at the 350Z file and
  it renders invisible. Patching `GLOBALB.BUN` to redirect them fails too: the
  engine reads the JDLZ-compressed `GlobalB.lzc` and ignores the `.BUN`.
* **Emptying `SOUND/*.abk`.** Startup dies. The banks are named individually
  and there is no empty `.abk` in stock to copy.
* **Emptying `ROUTESL4RA`.** `Routes*.bin` kills race opponents and minimap
  markers; `Paths*.bin` crashes custom race loading.
* **Emptying `FRONTEND/PLATFORMS`** or **`GLOBAL/GLOBALB.BUN`.** Both are
  literal-path and both kill startup silently.
* **Reducing polygons or texture resolution.** No tool writes NFSU2 track
  geometry back, and the stream bundles are sector-aligned with an external
  offset table (671 entries in the *smallest* region) — shrinking any payload
  invalidates every offset after it.

## Requirements

`bash`, `tar`, `xz`, `python3`, `iconv`, `wine`, and enough free RAM
(~4× the archive). Tested on Arch Linux with Wine 11.16.
