#!/bin/zsh
# Pixel compare of the reference-main page against the reference capture it was measured
# from (design/KIT.md "Compare"), in light and dark, with the design-from-app compare.swift.
# Usage: tools/compare.sh <reference prefix>
#   The prefix names the local captures: <prefix>-light.png and <prefix>-dark.png, 910 × 600 pt
#   at 2x. They live in the gitignored design/reference/ and never go in the repo.
#   SILVANUS_COMPARE_NO_SNAP=1   use the shots already taken instead of running tools/snap.sh
#   SILVANUS_COMPARE             where the results go (default /tmp/Silvanus-compare)
#   COMPARE_SWIFT                the design-from-app compare.swift (default: the bama plugin's)
#   SILVANUS_DEV_DIR, SILVANUS_SNAP_STORE, SILVANUS_SHOTS pass through to tools/snap.sh.
# For each mode it writes <out>/<mode>/ (the whole window) and <out>/<mode>-masked/ (the
# by-design differences painted over in both images): side-by-side.png, diff.png, overlay.png.
# It prints the share of differing pixels for both; the gate is under 2% on the masked window,
# counted over the pixels the masks leave.
set -u
here=${0:A:h}
prefix=${1:?usage: tools/compare.sh <reference prefix>}
out=${SILVANUS_COMPARE:-/tmp/Silvanus-compare}
shots=${SILVANUS_SHOTS:-/tmp/Silvanus-shots}
compare=${COMPARE_SWIFT:-$(ls -d $HOME/.claude/plugins/cache/bama/bama/*/skills/design/design-from-app/scripts/compare.swift 2>/dev/null | tail -1)}
[[ -f $compare ]] || { echo "compare.swift not found: set COMPARE_SWIFT"; exit 1; }

# The parts that differ by design, in points (x y w h). Why each is left out: design/KIT.md "Compare".
masks=(
  255 8 135 30    # view pill: our labels (Summary, My notes, Transcript) and the segment's width
  690 8 188 30    # trailing header controls: Quick Note mic and Start Recording, not folder and share
  236 544 647 52  # the reference's floating bottom bar; Silvanus has none
)

if [[ -z ${SILVANUS_COMPARE_NO_SNAP:-} ]]; then
  # The reference draws text without font smoothing (no stem darkening), so the snapshot does too.
  APP_COLORS=reference APP_SNAPSHOT_PAGES=reference-main "$here/snap.sh" -AppleFontSmoothing 0 | grep -v '^SNAPSHOT /' || exit 1
fi

rm -rf "$out"
mkdir -p "$out"
for mode in light dark; do
  ref=$prefix-$mode.png
  shot=$shots/reference-main-$mode.png
  [[ -f $ref ]] || { echo "no reference capture: $ref"; exit 1; }
  [[ -f $shot ]] || { echo "no snapshot: $shot"; exit 1; }
  whole=$(swift "$compare" "$ref" "$shot" "$out/$mode" | head -1)
  swift "$here/compare-mask.swift" "$ref" "$out/ref-$mode-masked.png" "${masks[@]}" > /dev/null
  covered=$(swift "$here/compare-mask.swift" "$shot" "$out/build-$mode-masked.png" "${masks[@]}" | awk '{print $2}')
  masked=$(swift "$compare" "$out/ref-$mode-masked.png" "$out/build-$mode-masked.png" "$out/$mode-masked" | head -1)
  # "N% of pixels differ (D of T)": count D over the pixels the masks leave.
  different=$(print -r -- "$masked" | sed -E 's/.*\(([0-9]+) of ([0-9]+)\).*/\1/')
  total=$(print -r -- "$masked" | sed -E 's/.*\(([0-9]+) of ([0-9]+)\).*/\2/')
  share=$(awk -v d=$different -v t=$total -v c=$covered 'BEGIN { printf "%.2f", d * 100 / (t - c) }')
  echo "$mode: whole window $whole"
  echo "$mode: masked ${share}% of unmasked pixels differ ($different of $((total - covered)))"
done
echo "results in $out"
