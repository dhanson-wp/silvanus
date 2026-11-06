#!/bin/zsh
# Renders the brand files in Brand/ into Resources/ (all gitignored):
#   Resources/AppIcon.icns                          the Dock, Finder, and About icon
#   Resources/menubar{,-recording}{,@2x}.png        template glyphs, 18 pt (18 and 36 px)
#   Resources/brand-colors.json                     a copy of Brand/colors.json, when there is one
# Each file comes from Brand/ when it's there, else from Brand/placeholder/. An icon
# iconset and a menubar.png/@2x pair in Brand/ are used as is; no recording glyph reuses the idle one.
# Needs only Command Line Tools: a Swift script draws the SVGs (tools/render_svg.swift)
# and iconutil packs the .icns. build.sh runs this when anything in Brand/ changed.
# Usage: tools/brand.sh
set -euo pipefail
here=${0:A:h}
repo=${here:h}
brand="$repo/Brand"
out="$repo/Resources"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

# pick <name> <ext>... : the first of Brand/<name>.<ext> or Brand/placeholder/<name>.<ext> that exists.
pick() {
  local name=$1; shift
  local dir ext
  for dir in "$brand" "$brand/placeholder"; do
    for ext in "$@"; do
      [[ -f "$dir/$name.$ext" ]] && { echo "$dir/$name.$ext"; return 0; }
    done
  done
  echo "brand: no $name.${1} in Brand/ or Brand/placeholder/" >&2
  return 1
}

render() { swift "$here/render_svg.swift" "$@"; }

# App icon: Brand/app-icon.iconset/ (the ten standard PNGs) is packed as is, never re-rendered.
# Otherwise a 1024 px source (it carries its own margin) is drawn at every size the .iconset wants.
if [[ -d "$brand/app-icon.iconset" ]]; then
  iconutil -c icns "$brand/app-icon.iconset" -o "$out/AppIcon.icns"
  echo "wrote Resources/AppIcon.icns from Brand/app-icon.iconset"
else
  icon=$(pick app-icon svg png)
  iconset="$work/AppIcon.iconset"
  mkdir -p "$iconset"
  render "$icon" "$work/icon-{px}.png" 16 32 64 128 256 512 1024
  for size in 16 32 128 256 512; do
    cp "$work/icon-$size.png" "$iconset/icon_${size}x${size}.png"
    cp "$work/icon-$((size * 2)).png" "$iconset/icon_${size}x${size}@2x.png"
  done
  iconutil -c icns "$iconset" -o "$out/AppIcon.icns"
  echo "wrote Resources/AppIcon.icns from ${icon#$repo/}"
fi

# Menu bar glyphs: single-color artwork, shown as template images.
# A Brand/<state>.png plus <state>@2x.png pair is copied as is (an 18 px PNG is never scaled up).
# With no menubar-recording.* in Brand/, the recording outputs reuse the idle glyph
# (the placeholder's recording glyph is never mixed in beside real artwork).
glyph() {
  local state=$1
  if [[ -f "$brand/$state.png" && -f "$brand/$state@2x.png" ]]; then
    cp "$brand/$state.png" "$out/$state.png"
    cp "$brand/$state@2x.png" "$out/$state@2x.png"
    echo "wrote Resources/$state.png and @2x from Brand/$state.png and @2x"
  else
    local src
    src=$(pick $state svg png) || return 1
    render "$src" "$work/$state-{px}.png" 18 36
    cp "$work/$state-18.png" "$out/$state.png"
    cp "$work/$state-36.png" "$out/$state@2x.png"
    echo "wrote Resources/$state.png and @2x from ${src#$repo/}"
  fi
}
has_brand_glyph() { [[ -f "$brand/$1.png" || -f "$brand/$1@2x.png" || -f "$brand/$1.svg" ]]; }
glyph menubar
if has_brand_glyph menubar-recording || ! has_brand_glyph menubar; then
  glyph menubar-recording
else
  cp "$out/menubar.png" "$out/menubar-recording.png"
  cp "$out/menubar@2x.png" "$out/menubar-recording@2x.png"
  echo "wrote Resources/menubar-recording.png and @2x from the idle glyph"
fi

# Brand colors feed the accent token only.
if [[ -f "$brand/colors.json" ]]; then
  cp "$brand/colors.json" "$out/brand-colors.json"
  echo "wrote Resources/brand-colors.json"
else
  rm -f "$out/brand-colors.json"
fi
