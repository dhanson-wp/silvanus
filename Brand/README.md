# Brand

Everything that carries the brand comes from this folder. Until the real files
arrive it holds a neutral placeholder in `placeholder/`: a plain rounded square
with a gray "s", and a circle outline for the menu bar. Nothing here is designed.

## Files expected

Drop these in `Brand/` (not in `placeholder/`). Each one that's present replaces
its placeholder.

- `app-icon.svg` (or a 1024 by 1024 `app-icon.png`): the Dock, Finder, and About icon. The artwork carries its own margin on the 1024 canvas; the placeholder's square is 824 wide, centered, which is Apple's macOS icon grid.
- `menubar.svg`: a single-color template glyph for the menu bar, idle state, drawn on an 18 pt square. Any opaque color works; macOS tints it.
- `menubar-recording.svg` (optional): the same glyph for the recording state.
- `wordmark.svg` (optional): for the welcome window and About.
- `colors.json` (optional): brand colors, for example `{"accent": "#2B6CB0"}`. These feed the accent token only; recording red and the neutral surfaces stay as the design kit measured them.

## One command

`tools/brand.sh` renders `Resources/AppIcon.icns`, the menu bar images (18 and 36 px), and `Resources/brand-colors.json` from these files. `./build.sh` runs it when anything in `Brand/` changed and copies the results into the app. Everything in `Resources/` is generated and gitignored; only this folder is committed. Code never names a brand file: it uses `Brand.appIcon`, `Brand.menuBarGlyph`, `Brand.menuBarRecordingGlyph`, and `Brand.accent` (`Sources/Silvanus/UI/Brand.swift`).

## Handoff note for Codex

Put the files in `Brand/`, run `tools/brand.sh` then `./build.sh`, and check the brand snapshots. Don't change views.

The brand snapshots are `about-light.png`, `about-dark.png`, and the menu bar images (`menubar-*` and `menubar-recording-*`, light and dark) that `tools/snap.sh` writes to `/tmp/Silvanus-shots`.
