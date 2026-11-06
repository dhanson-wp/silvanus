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
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
# Compiling it needs actool, which comes with Xcode; with Command Line Tools
# only, the build goes on without the icon.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
    if xcrun --find actool >/dev/null 2>&1; then
      "$here/tools/make_icon.sh"
    else
      echo "note: no actool (Command Line Tools only), so the bundle has no app icon"
    fi
  fi
  [[ -f "$car" ]] && cp -X "$car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
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
