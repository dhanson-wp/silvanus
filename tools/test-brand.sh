#!/bin/zsh
# Checks tools/brand.sh. On a clean copy of the repo it must write the icon and the
# menu bar images; with a different Brand/app-icon.svg dropped in, the .icns must
# change; with Brand/colors.json, the colors file must appear. Prints PASS or FAIL.
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
rm -rf "$work/repo/Brand/app-icon.svg" "$work/repo/Brand/app-icon.png"
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

(( fail )) && { echo "FAIL"; exit 1; }
echo "PASS"
