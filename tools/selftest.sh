#!/bin/zsh
# Runs the in-app self-test from the dev bundle (./build.sh) against a fresh
# folder in /tmp. Exit code 0 when every check passed. Never runs or changes
# the installed app, and never deletes saved window state.
set -u
app=~/Library/Developer/Silvanus/Silvanus.app/Contents/MacOS/Silvanus
[[ -x $app ]] || { echo "no dev bundle: run ./build.sh first"; exit 1; }
store=/tmp/Silvanus-self
rm -rf $store
mkdir -p $store
APP_STORE=$store $app -ApplePersistenceIgnoreState YES --selftest
