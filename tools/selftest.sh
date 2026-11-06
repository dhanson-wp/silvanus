#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.derekhanson.silvanus.savedState
store=/tmp/Silvanus-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store ~/Applications/Silvanus.app/Contents/MacOS/Silvanus --selftest
