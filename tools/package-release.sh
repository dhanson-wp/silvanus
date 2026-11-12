#!/bin/sh
# Packages a release build of Silvanus and assembles the download site around it.
#
#   ./build.sh --release
#   tools/package-release.sh ~/Library/Developer/Silvanus/Silvanus.app <output folder>
#
# Writes into the output folder (keep it outside this repository):
#   Silvanus-<version>-<build>.zip   the app, archived with ditto so the signature survives
#   latest.json                      the manifest install.sh reads
#   appcast.xml                      the in-app update feed (Sparkle), signed with the update key
#   index.html, llms.txt, install.sh, install-guide.txt, LICENSE.txt, robots.txt, brand/
#                                    the download page at get-silvanus.space.fast
#
# Publish the folder as a whole (see INSTALL.md, "Publishing a build"), and attach the zip,
# latest.json, and appcast.xml to the GitHub release.
#
# Environment, or the gitignored .env.local:
#   UPDATE_KEY_ACCOUNT  the Keychain account holding the private update key (required)
#   SPARKLE_BIN         Sparkle's bin folder (default: the one swift build fetched)
#   RELEASE_NOTES       an HTML file shown in the update window
#   FEED_BASE           where the files will be served (default: https://get-silvanus.space.fast)
#
# It doesn't build, sign the app, upload, or publish anything. It refuses an app whose signature
# doesn't verify, whose signer install.sh doesn't trust, or whose update key doesn't match.
#
# The same steps as PressShot's scripts/package-release.sh (github.com/dhanson-wp/pressshot).
set -eu

BUNDLE_ID="com.derekhanson.silvanus"
PLIST=/usr/libexec/PlistBuddy
die() { printf 'package-release: %s\n' "$*" >&2; exit 1; }

[ $# -eq 2 ] || die "usage: tools/package-release.sh /path/to/Silvanus.app /path/to/output-folder"
APP="${1%/}"; OUT="${2%/}"
[ -d "$APP" ] && [ "$(basename "$APP")" = "Silvanus.app" ] || die "$APP is not a Silvanus.app bundle."
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
case "$OUT/" in "$REPO_ROOT"/*) die "keep release files outside the repository ($OUT is inside it)." ;; esac

# Read one line of .env.local; never source the file.
env_local() {
    [ -f "$REPO_ROOT/.env.local" ] || return 0
    grep -m1 "^$1=" "$REPO_ROOT/.env.local" | sed -e "s/^$1=//" -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" || true
}
UPDATE_KEY_ACCOUNT="${UPDATE_KEY_ACCOUNT:-$(env_local UPDATE_KEY_ACCOUNT)}"
[ -n "$UPDATE_KEY_ACCOUNT" ] || die "set UPDATE_KEY_ACCOUNT (in the environment or .env.local) to the Keychain account of the update key."
FEED_BASE="${FEED_BASE:-https://get-silvanus.space.fast}"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/Library/Developer/Silvanus/build/artifacts/sparkle/Sparkle/bin}"
[ -x "$SPARKLE_BIN/sign_update" ] && [ -x "$SPARKLE_BIN/generate_keys" ] || die "couldn't find Sparkle's sign_update. Run ./build.sh, or set SPARKLE_BIN."

/usr/bin/codesign --verify --deep --strict "$APP" 2>/dev/null || die "the app's code signature doesn't verify. Sign it first."
INFO="$APP/Contents/Info.plist"
[ "$("$PLIST" -c 'Print :CFBundleIdentifier' "$INFO")" = "$BUNDLE_ID" ] || die "unexpected bundle identifier."

# The signer must be one the installer trusts, or every install would fail after download.
SIGNERS="$(sed -n 's/^[[:space:]]*TRUSTED_SIGNERS="\(.*\)"$/\1/p' "$REPO_ROOT/install.sh")"
[ -n "$SIGNERS" ] || die "couldn't read TRUSTED_SIGNERS from install.sh."
OK=0
for leaf in $SIGNERS; do
    if /usr/bin/codesign --verify -R="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$leaf\"" "$APP" 2>/dev/null; then OK=1; fi
done
[ "$OK" = 1 ] || die "this app is signed by a certificate install.sh doesn't list in TRUSTED_SIGNERS."

# The app only accepts an update signed with the key whose public half is in its Info.plist.
APP_KEY="$("$PLIST" -c 'Print :SUPublicEDKey' "$INFO" 2>/dev/null || true)"
FEED_URL="$("$PLIST" -c 'Print :SUFeedURL' "$INFO" 2>/dev/null || true)"
[ "$FEED_URL" = "$FEED_BASE/appcast.xml" ] || die "this build's update feed (${FEED_URL:-none}) isn't $FEED_BASE/appcast.xml. Build with ./build.sh --release."
KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" --account "$UPDATE_KEY_ACCOUNT" -p 2>/dev/null || true)"
[ -n "$APP_KEY" ] && [ "$APP_KEY" = "$KEYCHAIN_KEY" ] || die "the app's update key doesn't match the one in the Keychain."

VERSION="$("$PLIST" -c 'Print :CFBundleShortVersionString' "$INFO")"
BUNDLE_VERSION="$("$PLIST" -c 'Print :CFBundleVersion' "$INFO")"
MIN_OS="$("$PLIST" -c 'Print :LSMinimumSystemVersion' "$INFO")"
BUILD="$(/usr/bin/codesign -dvvv "$APP" 2>&1 | sed -n 's/^CDHash=//p' | head -1)"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || die "couldn't read the app's version or build hash."
ARCHS="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/Silvanus")"

ZIP_NAME="Silvanus-$VERSION-$(printf '%s' "$BUILD" | cut -c1-12).zip"
rm -f "$OUT"/Silvanus-*.zip
/usr/bin/ditto -c -k --keepParent "$APP" "$OUT/$ZIP_NAME"
SHA="$(/usr/bin/shasum -a 256 "$OUT/$ZIP_NAME" | cut -d' ' -f1)"
SIZE="$(/usr/bin/stat -f %z "$OUT/$ZIP_NAME")"

cat > "$OUT/latest.json" <<EOF
{
  "bundleID": "$BUNDLE_ID",
  "version": "$VERSION",
  "build": "$BUILD",
  "minimumSystemVersion": "$MIN_OS",
  "architectures": "$ARCHS",
  "published": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "zip": { "name": "$ZIP_NAME", "sha256": "$SHA", "size": $SIZE }
}
EOF
[ "$(/usr/bin/plutil -extract zip.sha256 raw -o - -- "$OUT/latest.json" 2>/dev/null)" = "$SHA" ] || die "wrote an invalid latest.json."

SIGNATURE="$("$SPARKLE_BIN/sign_update" --account "$UPDATE_KEY_ACCOUNT" "$OUT/$ZIP_NAME")" || die "couldn't sign the zip for updates."
case "$SIGNATURE" in *'sparkle:edSignature="'*) ;; *) die "sign_update returned an unexpected result." ;; esac
NOTES=""
if [ -n "${RELEASE_NOTES:-}" ]; then
    [ -f "$RELEASE_NOTES" ] || die "RELEASE_NOTES ($RELEASE_NOTES) isn't a file."
    if grep -q ']]>' "$RELEASE_NOTES"; then die "RELEASE_NOTES can't contain ]]>."; fi
    NOTES="      <description><![CDATA[$(cat "$RELEASE_NOTES")]]></description>"
fi
cat > "$OUT/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Silvanus</title>
    <link>$FEED_BASE/</link>
    <item>
      <title>Silvanus $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUNDLE_VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
$NOTES
      <enclosure url="$FEED_BASE/$ZIP_NAME" $SIGNATURE type="application/octet-stream" />
    </item>
  </channel>
</rss>
APPCAST
/usr/bin/xmllint --noout "$OUT/appcast.xml" 2>/dev/null || die "wrote an invalid appcast.xml."

# The download page and what it links to.
cp "$REPO_ROOT/download/index.html" "$REPO_ROOT/download/llms.txt" "$REPO_ROOT/download/robots.txt" "$OUT/"
cp "$REPO_ROOT/install.sh" "$OUT/install.sh"
cp "$REPO_ROOT/INSTALL.md" "$OUT/install-guide.txt"
cp "$REPO_ROOT/LICENSE" "$OUT/LICENSE.txt"
mkdir -p "$OUT/brand"
cp "$REPO_ROOT/Brand/app-icon.png" "$OUT/brand/icon-1024.png"
cp "$REPO_ROOT/Brand/app-icon.iconset/icon_256x256.png" "$OUT/brand/icon-256.png"
cp "$REPO_ROOT/Brand/app-icon.iconset/icon_32x32.png" "$OUT/brand/favicon-32.png"
cp "$REPO_ROOT/Brand/app-icon.iconset/icon_128x128@2x.png" "$OUT/brand/apple-touch-icon.png"
cp "$REPO_ROOT/Brand/readme/summary-light.png" "$OUT/brand/summary-light.png"
cp "$REPO_ROOT/Brand/readme/transcript-dark.png" "$OUT/brand/transcript-dark.png"

printf 'Packaged Silvanus %s (build %s)\n  %s\n  %s\n  %s\n  and the download page, in %s\n' \
    "$VERSION" "$BUILD" "$OUT/$ZIP_NAME" "$OUT/latest.json" "$OUT/appcast.xml" "$OUT"
