# Install Silvanus

Silvanus is a Mac app that records your meetings and writes the transcript, notes, and to-dos on your Mac. It needs a Mac with Apple silicon and macOS 26 or newer.

## Quick install

Paste this into Terminal and press Return:

```sh
curl -fsSL https://get-silvanus.space.fast/install.sh | sh
```

It downloads the latest build, checks it, puts Silvanus in your Applications folder, and opens it. After that, Silvanus updates itself: it checks once a day and asks before installing anything. You can check any time with Silvanus > Check for Updates…, and turn the daily check off in Settings > General. Running the same line again also upgrades.

Silvanus isn't notarized by Apple yet. Installing from Terminal avoids the "can't be opened" warning you'd get from a browser download.

## After it opens

No script or agent can do these for you; macOS asks you directly.

1. **Allow the microphone and system audio.** Start a recording (Start Recording, or ⇧⌘R). Silvanus asks for the microphone (your side of the call) and system audio (everyone else) the first time you record, never at launch.
2. **Let the speech model download.** The first transcript downloads Parakeet (about 450 MB) on its own.
3. **Optional extras.** Connect a calendar in Settings > Calendar so recordings take the event's title and attendees. For to-dos and summaries, download a Gemma 4 model from Home or Settings > Summaries (2.6 GB or 7.4 GB).

## For agents

The installer never prompts, so you can run it for someone. Ask for `--json` and read the single JSON line on stdout; everything else goes to stderr.

```sh
curl -fsSL https://get-silvanus.space.fast/install.sh | sh -s -- --json
```

| Option | Environment variable | What it does |
| --- | --- | --- |
| `--check` | `SILVANUS_CHECK=1` | Report installed and latest builds; change nothing |
| `--json` | `SILVANUS_JSON=1` | One JSON result line on stdout |
| `--no-open` | `SILVANUS_NO_OPEN=1` | Don't launch Silvanus afterwards |
| `--no-quit` | `SILVANUS_NO_QUIT=1` | Fail (exit 5) instead of quitting a running Silvanus |
| `--reinstall` | `SILVANUS_REINSTALL=1` | Install even when this build is already there |
| `--dir <folder>` | `SILVANUS_INSTALL_DIR` | Where `Silvanus.app` goes |
| `--feed <url>` | `SILVANUS_FEED` | Folder URL holding `latest.json` and the archive |

Result fields: `status`, `version`, `build`, `previous_build`, `path`, `message`, and `needs_human` (the steps above, as a list, after a fresh install).

| `status` | Meaning |
| --- | --- |
| `installed` | Fresh install finished |
| `upgraded` | A different build was replaced |
| `current` | This build was already installed; nothing changed |
| `update_available` | `--check` only: a newer build exists |
| `not_installed` | `--check` only: Silvanus isn't on this Mac |
| `failed` | See `message` and the exit code |

| Exit code | Meaning |
| --- | --- |
| 0 | Done, or nothing to do |
| 1 | Unexpected failure; the previous copy was put back if there was one |
| 2 | Bad option, run as root, or no feed configured |
| 3 | This Mac can't run Silvanus (it needs Apple silicon and macOS 26) |
| 4 | Download or verification failed; nothing was installed |
| 5 | Silvanus is running and `--no-quit` was given, or it didn't quit |

Guidance for agents:

- Silvanus may be recording a call. Upgrading asks it to quit, and while a meeting records it asks the person first, so the installer gives up with exit 5 rather than end a recording. Pass `--no-quit` to never ask, and tell the person to quit Silvanus themselves.
- After `installed`, relay every item in `needs_human` to the person. Don't click through the macOS permission prompts on their behalf.
- Don't run the installer with `sudo`.
- To confirm it's running: `pgrep -x Silvanus`.
- Meetings are plain files under `~/Silvanus/library`; installing or upgrading never touches them.

## What the installer checks

- The archive's size and SHA-256 match `latest.json`.
- The archive holds exactly one `Silvanus.app`.
- The app's signature is valid and comes from a certificate listed in `TRUSTED_SIGNERS` in `install.sh`.
- The app's build hash matches the one in `latest.json`.

`latest.json` itself is trusted over HTTPS. In-app updates are checked the same way Sparkle always checks them: each archive carries an EdDSA signature that must match the public key built into Silvanus.

## Publishing a build (maintainers)

1. Bump `CFBundleShortVersionString` in `Info.plist.in`, then run `./build.sh --release`. A release build signs with the certificate in `.env.local` (listed in `TRUSTED_SIGNERS`) and turns on in-app updates; plain builds never offer to update themselves.
2. Run `tools/package-release.sh ~/Library/Developer/Silvanus/Silvanus.app <output folder>`, with the output folder outside this repository. It needs `UPDATE_KEY_ACCOUNT` in `.env.local`: the Keychain account that holds the private update key. Set `RELEASE_NOTES` to an HTML file to show notes in the update window.
3. Publish the whole output folder to the download Space: `sf publish <output folder> --space get-silvanus`.
4. Tag the commit `v<version>` and attach the zip, `latest.json`, and `appcast.xml` to a GitHub release.
