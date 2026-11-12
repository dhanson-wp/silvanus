#!/bin/zsh
# Builds Silvanus into the dev bundle ~/Library/Developer/Silvanus/Silvanus.app
# (SILVANUS_DEV_DIR moves it, so a second checkout can build side by side).
# Build products live in ~/Library/Developer/Silvanus, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
# A plain build never touches ~/Applications.
#
# Usage: ./build.sh             release build into the dev bundle
#        ./build.sh --debug     debug build into the dev bundle
#        ./build.sh --install   then copy the dev bundle to ~/Applications/Silvanus.app
#        ./build.sh --open      install, then quit the running copy and open the new one
#        ./build.sh --release   a release build: turns on in-app updates (tools/package-release.sh)
#
# Signing: SIGN_IDENTITY from the environment, else the SIGN_IDENTITY=... line
# in the gitignored .env.local, else ad hoc (fine for your own Mac).
set -euo pipefail
here=${0:A:h}
name="Silvanus"
dev="${SILVANUS_DEV_DIR:-$HOME/Library/Developer/$name}"
scratch="$dev/build"
config=release
install=0
relaunch=0
release=0
# In-app updates (Sparkle). Only --release builds carry the feed and the public key, so a dev
# build never offers to replace itself. The key's private half signs each update and lives in
# the release Mac's Keychain; tools/package-release.sh checks the two match.
feed_url="https://get-silvanus.space.fast/appcast.xml"
update_key="H8bhXvsHALRgmM1xrwjA8VXsXNaWjc4s/Wu+4HuFyUM="
for arg in "$@"; do
  case "$arg" in
    --debug) config=debug ;;
    --install) install=1 ;;
    --open) install=1; relaunch=1 ;;
    --release) release=1 ;;
    *) echo "usage: ./build.sh [--debug] [--install] [--open] [--release]" >&2; exit 2 ;;
  esac
done

identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" && -f "$here/.env.local" ]]; then
  # Read the one line; never source the file.
  identity=$(grep -m1 '^SIGN_IDENTITY=' "$here/.env.local" | sed -e 's/^SIGN_IDENTITY=//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" || true)
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" "$here/Package.swift" -newer "$bin" \( -name '*.swift' \) | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

app="$dev/$name.app"
rm -rf "${app:?}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
(( release )) || { feed_url=""; update_key=""; }
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s|__FEED_URL__|$feed_url|" -e "s|__UPDATE_KEY__|$update_key|" \
  "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The brand: Brand/ -> Resources/ (AppIcon.icns, menu bar images, brand-colors.json),
# rebuilt by tools/brand.sh when anything in Brand/ or the renderer is newer than the outputs.
icns="$here/Resources/AppIcon.icns"
if [[ ! -f "$icns" || -n "$(find "$here/Brand" "$here/tools/brand.sh" "$here/tools/render_svg.swift" -type f -newer "$icns" | head -1)" ]]; then
  "$here/tools/brand.sh" >/dev/null
fi
for file in AppIcon.icns menubar.png menubar@2x.png menubar-recording.png menubar-recording@2x.png brand-colors.json; do
  [[ -f "$here/Resources/$file" ]] && cp -X "$here/Resources/$file" "$app/Contents/Resources/"
done
# llama.cpp's and Sparkle's frameworks, next to the binary after the build: into the bundle,
# where the binary looks for them.
mkdir -p "$app/Contents/Frameworks"
for framework in llama Sparkle; do
  [[ -d "$scratch/$config/$framework.framework" ]] || { echo "build failed: $framework.framework is missing"; exit 1; }
  ditto "$scratch/$config/$framework.framework" "$app/Contents/Frameworks/$framework.framework"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$app/Contents/MacOS/$name" 2>/dev/null || true
xattr -cr "$app"
sign() { codesign --force --sign "$identity" "$@" 2>&1 | grep -v "replacing existing signature" || true; }
sign "$app/Contents/Frameworks/llama.framework"
# Sparkle's helpers inside out, then the framework (Sparkle's guide for signing outside Xcode).
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$sparkle/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "built $app (signed: ${identity})"

if (( install )); then
  installed="$HOME/Applications/$name.app"
  mkdir -p "$HOME/Applications"
  rm -rf "${installed:?}"
  ditto "$app" "$installed"
  echo "installed $installed"
fi

if (( relaunch )); then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$installed"
fi
