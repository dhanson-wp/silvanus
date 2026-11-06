#!/bin/zsh
# Checks tools/brand.sh. On a clean copy of the repo it must write the icon and the
# menu bar images; with a different Brand/app-icon.svg dropped in, the .icns must
# change; with Brand/colors.json, the colors file must appear. Also: an iconset in
# Brand/ is packed as is, menubar.png and @2x are copied as is, and with no
# menubar-recording.* the idle glyph is reused. Prints PASS or FAIL.
set -u
here=${0:A:h}
repo=${here:h}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

# A temp copy of the sources only (no .git, no build output, no old Resources).
mkdir -p "$work/repo"
cp -R "$repo/Brand" "$repo/tools" "$work/repo/"
# Start from the placeholder path: no icon, iconset, glyphs, or colors in Brand/.
rm -rf "$work/repo/Brand/app-icon.svg" "$work/repo/Brand/app-icon.png" "$work/repo/Brand/app-icon.iconset" \
  "$work/repo/Brand/menubar.png" "$work/repo/Brand/menubar@2x.png" "$work/repo/Brand/colors.json"
r="$work/repo"

"$r/tools/brand.sh" >/dev/null 2>"$work/err" || { cat "$work/err"; echo "FAIL brand.sh on a clean copy"; exit 1; }
for f in AppIcon.icns menubar.png menubar@2x.png menubar-recording.png menubar-recording@2x.png; do
  check "clean copy writes $f" "[[ -s $r/Resources/$f ]]"
done
check "no colors file without Brand/colors.json" "[[ ! -e $r/Resources/brand-colors.json ]]"
check "icns is an icns file" "[[ \$(head -c 4 $r/Resources/AppIcon.icns) == icns ]]"
check "menu bar images are 18 and 36 px" "[[ \$(sips -g pixelWidth $r/Resources/menubar.png | awk '/pixelWidth/{print \$2}') == 18 && \$(sips -g pixelWidth $r/Resources/menubar@2x.png | awk '/pixelWidth/{print \$2}') == 36 ]]"
before=$(shasum "$r/Resources/AppIcon.icns" | cut -d' ' -f1)

cat > "$r/Brand/app-icon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect x="100" y="100" width="824" height="824" rx="185" fill="#2B6CB0"/>
</svg>
SVG
echo '{"accent": "#2B6CB0"}' > "$r/Brand/colors.json"
"$r/tools/brand.sh" >/dev/null 2>"$work/err" || { cat "$work/err"; echo "FAIL brand.sh with a dropped-in icon"; exit 1; }
after=$(shasum "$r/Resources/AppIcon.icns" | cut -d' ' -f1)
check "a dropped-in app-icon.svg changes the icns checksum" "[[ $before != $after ]]"
check "colors.json is copied to brand-colors.json" "cmp -s $r/Brand/colors.json $r/Resources/brand-colors.json"

rm "$r/Brand/colors.json"
"$r/tools/brand.sh" >/dev/null 2>&1
check "removing colors.json removes brand-colors.json" "[[ ! -e $r/Resources/brand-colors.json ]]"

# An iconset in Brand/ is used byte for byte; menubar.png and @2x are copied as is;
# with no menubar-recording.*, the recording outputs equal the idle ones.
mkdir -p "$r/Brand/app-icon.iconset"
cp "$repo"/Brand/app-icon.iconset/*.png "$r/Brand/app-icon.iconset/" 2>/dev/null
cp "$repo/Brand/menubar.png" "$repo/Brand/menubar@2x.png" "$r/Brand/" 2>/dev/null
check "the repo ships a ten-file iconset" "[[ \$(ls $r/Brand/app-icon.iconset/*.png | wc -l) -eq 10 ]]"
check "the repo ships menubar.png and menubar@2x.png" "[[ -s $r/Brand/menubar.png && -s $r/Brand/menubar@2x.png ]]"
"$r/tools/brand.sh" >/dev/null 2>"$work/err" || { cat "$work/err"; echo "FAIL brand.sh with an iconset"; exit 1; }
iconutil -c iconset "$r/Resources/AppIcon.icns" -o "$work/decoded.iconset" 2>/dev/null
same=1
for f in "$r"/Brand/app-icon.iconset/*.png; do
  # iconutil may re-encode a size it stores twice (16@2x and 32), so compare pixel sizes per name.
  [[ $(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}') == $(sips -g pixelWidth "$work/decoded.iconset/${f:t}" | awk '/pixelWidth/{print $2}') ]] || same=0
done
check "the icns decodes to the iconset's ten PNG sizes" "[[ \$(ls $work/decoded.iconset | wc -l) -eq 10 && $same -eq 1 ]]"
check "menubar.png is copied byte for byte" "cmp -s $r/Brand/menubar.png $r/Resources/menubar.png"
check "menubar@2x.png is copied byte for byte" "cmp -s $r/Brand/menubar@2x.png $r/Resources/menubar@2x.png"
check "no recording glyph: menubar-recording.png equals the idle one" "cmp -s $r/Resources/menubar.png $r/Resources/menubar-recording.png"
check "no recording glyph: menubar-recording@2x.png equals the idle one" "cmp -s $r/Resources/menubar@2x.png $r/Resources/menubar-recording@2x.png"

# A recording glyph, when there is one, still wins.
cp "$r/Brand/placeholder/menubar-recording.svg" "$r/Brand/menubar-recording.svg"
"$r/tools/brand.sh" >/dev/null 2>"$work/err" || { cat "$work/err"; echo "FAIL brand.sh with a recording glyph"; exit 1; }
check "a menubar-recording.svg is still rendered" "! cmp -s $r/Resources/menubar.png $r/Resources/menubar-recording.png"

(( fail )) && { echo "FAIL"; exit 1; }
echo "PASS"
