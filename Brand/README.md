# Brand

Everything that carries the brand comes from this folder. `placeholder/` holds a
neutral fallback (a plain rounded square with a gray "s", and a circle outline for
the menu bar) for any file that's missing.

## Current brand

The scribe icon and palette are in place. `Brand/` holds `app-icon.png` (the 1024 master), `app-icon.iconset/` (the ten production PNGs, packed into the `.icns` as is), `menubar.png` and `menubar@2x.png` (18 and 36 px, copied as is), and `colors.json` (the palette's colors and light and dark theme tokens, plus the gold `accent`). There's no `menubar-recording` glyph yet, so the recording state reuses the idle one. `placeholder/` stays as the fallback for anything missing.

## Files expected

Drop these in `Brand/` (not in `placeholder/`). Each one that's present replaces
its placeholder.

- `app-icon.iconset/` (the ten standard PNGs, used as is) or `app-icon.svg` (or a 1024 by 1024 `app-icon.png`): the Dock, Finder, and About icon. The artwork carries its own margin on the 1024 canvas; the placeholder's square is 824 wide, centered, which is Apple's macOS icon grid.
- `menubar.png` and `menubar@2x.png` (copied as is) or `menubar.svg`: a single-color template glyph for the menu bar, idle state, drawn on an 18 pt square. Any opaque color works; macOS tints it.
- `menubar-recording.svg` (optional): the same glyph for the recording state; without one, the idle glyph is reused.
- `wordmark.svg` (optional): for the welcome window and About.
- `colors.json` (optional): brand colors, for example `{"accent": "#2B6CB0"}`. These feed the accent token only; recording red and the neutral surfaces stay as the design kit measured them.

## One command

`tools/brand.sh` renders `Resources/AppIcon.icns`, the menu bar images (18 and 36 px), and `Resources/brand-colors.json` from these files. `./build.sh` runs it when anything in `Brand/` changed and copies the results into the app. Everything in `Resources/` is generated and gitignored; only this folder is committed. Code never names a brand file: it uses `Brand.appIcon`, `Brand.menuBarGlyph`, `Brand.menuBarRecordingGlyph`, and `Brand.accent` (`Sources/Silvanus/UI/Brand.swift`).

## After a change

Put the files in `Brand/`, run `tools/brand.sh` then `./build.sh`, and check the brand snapshots that `tools/snap.sh` writes to `/tmp/Silvanus-shots`: `about-light.png`, `about-dark.png`, and the menu bar images (`menubar-*` and `menubar-recording-*`, light and dark). Don't change views.

## README images

`readme/` holds the images the top-level README shows: the banner, and four screenshots taken by `tools/snap.sh` from the made-up seed meetings. The app never reads them.
