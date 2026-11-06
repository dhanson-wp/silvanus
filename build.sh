#!/bin/zsh
# Builds Silvanus into the dev bundle ~/Library/Developer/Silvanus/Silvanus.app.
# Build products live in ~/Library/Developer/Silvanus, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
# A plain build never touches ~/Applications.
#
# Usage: ./build.sh             release build into the dev bundle
#        ./build.sh --debug     debug build into the dev bundle
#        ./build.sh --install   then copy the dev bundle to ~/Applications/Silvanus.app
#        ./build.sh --open      install, then quit the running copy and open the new one
#
# Signing: SIGN_IDENTITY from the environment, else the SIGN_IDENTITY=... line
# in the gitignored .env.local, else ad hoc (fine for your own Mac).
set -euo pipefail
here=${0:A:h}
name="Silvanus"
dev="$HOME/Library/Developer/$name"
scratch="$dev/build"
config=release
install=0
relaunch=0
for arg in "$@"; do
  case "$arg" in
    --debug) config=debug ;;
    --install) install=1 ;;
    --open) install=1; relaunch=1 ;;
    *) echo "usage: ./build.sh [--debug] [--install] [--open]" >&2; exit 2 ;;
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
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The brand: Brand/ -> Resources/ (AppIcon.icns, menu bar images, brand-colors.json),
# rebuilt by tools/brand.sh when anything in Brand/ or the renderer is newer than the outputs.
icns="$here/Resources/AppIcon.icns"
if [[ ! -f "$icns" || -n "$(find "$here/Brand" "$here/tools/brand.sh" "$here/tools/render_svg.swift" -type f -newer "$icns" | head -1)" ]]; then
  "$here/tools/brand.sh" >/dev/null
fi
for file in AppIcon.icns menubar.png menubar@2x.png menubar-recording.png menubar-recording@2x.png brand-colors.json; do
  [[ -f "$here/Resources/$file" ]] && cp -X "$here/Resources/$file" "$app/Contents/Resources/"
done
xattr -cr "$app"
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
