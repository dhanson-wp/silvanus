#!/bin/zsh
# Runs the in-app self-test from the dev bundle (./build.sh) against a fresh
# folder in /tmp. Exit code 0 when every check passed. Never runs or changes
# the installed app, and never deletes saved window state.
set -u
# SILVANUS_DEV_DIR and SILVANUS_SELFTEST_STORE move the dev bundle and the test folder.
app=${SILVANUS_DEV_DIR:-$HOME/Library/Developer/Silvanus}/Silvanus.app/Contents/MacOS/Silvanus
[[ -x $app ]] || { echo "no dev bundle: run ./build.sh first"; exit 1; }
store=${SILVANUS_SELFTEST_STORE:-/tmp/Silvanus-self}
rm -rf "$store"
mkdir -p "$store"
APP_STORE=$store "$app" -ApplePersistenceIgnoreState YES --selftest
