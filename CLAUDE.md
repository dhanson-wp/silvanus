# Silvanus

A native macOS app in SwiftUI that records meetings and turns them into
transcripts, all on this Mac, with no server. It builds with Command Line
Tools only: a Swift package, no Xcode project. There is no SwiftData: storage
is folders of plain files (Markdown and JSON), one folder per meeting.

## Layout

- `Sources/Silvanus/` the app. `App.swift` has the window, menus, and where the data lives (`Store`).
- `Sources/Silvanus/AppDefaults.swift` the one place the app reads and writes defaults.
- `Sources/SilvanusKit/` rules and data logic with no SwiftUI. Tests in `Tests/SilvanusKitTests/`.
- `Package.swift` a Swift package. FluidAudio (speech recognition) is pinned exactly and linked to the app target only.
- `build.sh` builds and signs the dev bundle `~/Library/Developer/Silvanus/Silvanus.app`.
- `Brand/` the brand files (app icon, menu bar glyph, colors) with a neutral placeholder. `tools/brand.sh` renders them into the gitignored `Resources/`; `build.sh` runs it and copies the results into the bundle. Code reads them only through `Brand` (`UI/Brand.swift`). `tools/test-brand.sh` checks the script. See `Brand/README.md`.
- `docs/STORIES.md` the user stories, `docs/GLOSSARY.md` every word on screen, `docs/FIXLOG.md` bugs worth remembering and the rule each one left.

## Build and check

- Build: `./build.sh` (add `--debug` for a debug build). It builds the dev bundle and prints its path. It never touches `~/Applications`. The build shows warnings; fix the ones from our code.
- Install: `./build.sh --install` copies the dev bundle to `~/Applications/Silvanus.app`; `--open` also quits the running copy and opens the new one. Use them only when Derek says so: the installed copy may be recording a call.
- Signing: `SIGN_IDENTITY` from the environment, else the `SIGN_IDENTITY=...` line in the gitignored `.env.local`, else ad hoc.
- Unit tests: `tools/test.sh` (adds the Command Line Tools flags Swift Testing needs).
- A second checkout (a worktree) builds and tests side by side with `SILVANUS_DEV_DIR=~/Library/Developer/Silvanus-<name>` set for `build.sh`, `tools/test.sh`, `tools/snap.sh`, and `tools/selftest.sh`. `SILVANUS_SNAP_STORE`, `SILVANUS_SHOTS`, and `SILVANUS_SELFTEST_STORE` move their /tmp folders.
- Self-test (the app's real functions on a /tmp folder): `tools/selftest.sh`. Exit 0 when every check passes. Add a check for every story with logic in `SelfTest.swift`.
- Audio: no check opens the microphone or call audio, or asks for a permission. `APP_SELFTEST_AUDIO=1 tools/selftest.sh` adds the after-call pass on two tracks spoken with `say` (it loads the speech model, downloading it the first time). `APP_TRANSCRIBE_FILE=<audio file>` on the dev binary prints one file's words with times; `APP_TRANSCRIBE=<meeting id>` with `APP_STORE` runs the after-call pass on that meeting's `audio/` folder.
- After every UI change, take snapshots and look at them: `tools/snap.sh`.
  It writes `/tmp/Silvanus-shots/<page>-light.png` and `-dark.png` for every sidebar page, `settings-<pane>-light.png` and `-dark.png` for every Settings pane, and the brand set (`about-*`, `menubar-*`, `menubar-recording-*`), then quits. `APP_SNAPSHOT_PAGES=all,settings tools/snap.sh` limits the pages.
  For a panel, sheet, or popover, add a capture to `Snapshot.swift` like the Settings loop.
- `snap.sh` and `selftest.sh` run the dev bundle's binary with `APP_STORE` in /tmp and `-ApplePersistenceIgnoreState YES`. Never run the installed app, never use `open` or `osascript` on it, and never delete its saved state.
- Snapshots and the self-test refuse to run without `APP_STORE`. Never test against the real meetings folder.
- Defaults: every read and write goes through `AppDefaults.shared`, including `@AppStorage(..., store: AppDefaults.shared)`. Test, snapshot, and self-test runs get their own suite, so they never change the real settings.
- Then check the grid: `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/Silvanus-shots/*-layout.json`. Both print PASS.
- A change is done when the build has no warnings from our code, the tests and grid checks pass, and you looked at the light and dark snapshots.

## Public repo

This repo is public. `tools/check-public.sh` runs as the pre-commit hook (`tools/install-hooks.sh` sets it up) and blocks what doesn't belong. Run `tools/check-public.sh --tree` before asking to push.

- Never commit meeting data (audio, transcripts, notes), secrets, signing material, Keychain item names, or absolute home paths (write `~`).
- Never commit real people, partners, customers, colleagues, internal project names, or internal URLs. Seed data, tests, fixtures, and examples use fictional meetings and people ("Acme kickoff", "Sam Rivera").
- No planning docs, research, or reference screenshots of other apps. Images live only in `Brand/` and `Icon/`.
- Code adapted from another project keeps its attribution comment, and its license goes in `THIRD-PARTY-NOTICES.md`.

## Design rules

- Window chrome is custom and measured from the design kit; menus, shortcuts, Settings, and accessibility stay native.
- The accent is the brand's, from the design kit (`Ink.accent`, fill only; `Ink.accentText` for accent text). People can't pick another. Settings > Appearance chooses System, Light, or Dark (`AppDefaults.appearance`, applied with `NSApp.appearance`).
- Views read only `Ink.*`, `KitType`, `Metric`, `Motion`, and `KitIcon`. Never hard-code colors, radii, or durations in views.
- Spacing comes from `Space` in `UI/Grid.swift`, on a 4 pt grid. Mark custom pages and cards with `.gridArea` and `.gridProbe`.
- Windows open calm: `.noInitialFocus()` on every window and sheet (no focus ring or selected text on open), `.fitsContent()` on sheets (no scroll bar with nothing to scroll). System scroll bars. Both in `UI/WindowBehavior.swift`.
- Settings open inside the main window (⌘, or Settings…), not in their own window: the list takes the sidebar column and the pane the canvas (`Screens/SettingsScreen.swift`). One pane per topic: add a case to `SettingsPane`, and a row per setting with `SettingRow`. Switches are `KitSwitchStyle`; buttons are `KitButtonStyle`.
- Colors: `.primary`, `.secondary`, `.tint`, and system colors. Never fixed grays or white for text.
- Every action has a menu bar item and a keyboard shortcut.
- `Label` for icon and text pairs. SF Symbols for icons.
- `ContentUnavailableView` for empty states.
- Liquid Glass belongs to floating controls only, never to content.
- Never put a live timer or other per-second content in a `MenuBarExtra` label: it re-lays out the menu bar every tick and froze the app once (`docs/FIXLOG.md`).
- Words on screen come from `docs/GLOSSARY.md`: one name per idea.

## Skills

The bama plugin has a skill for each step: `mac-design` (design rules),
`design-system` (accent and tokens), `layout-grid`, `ux-design`,
`swift-swiftui`, `os-integrations`, `performance`, `build-and-verify`,
`test-mac-app`, `app-icon`, `user-stories`, and `improve-loop`. Use them.

## Git

- Commit after each working change, with a message that says what the user can now do.
- Never push without Derek's go-ahead.
