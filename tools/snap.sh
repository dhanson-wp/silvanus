#!/bin/zsh
# Snapshots of every page in light and dark, on a fresh test folder, from the
# dev bundle (./build.sh). Never runs or changes the installed app, and never
# deletes saved window state: -ApplePersistenceIgnoreState skips it instead.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
set -u
app=~/Library/Developer/Silvanus/Silvanus.app/Contents/MacOS/Silvanus
[[ -x $app ]] || { echo "no dev bundle: run ./build.sh first"; exit 1; }
store=/tmp/Silvanus-test
shots=/tmp/Silvanus-shots
rm -rf $store $shots
mkdir -p $store
APP_SEED=1 APP_STORE=$store APP_SNAPSHOT=$shots $app -ApplePersistenceIgnoreState YES
