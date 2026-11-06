#!/bin/bash
# Tests for tools/check-public.sh. Builds throwaway git repos and checks what the guard flags.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-public.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Built in pieces so this file never holds the literal home-directory prefix.
HOMEDIR="/Us""ers/"
PASSED=0
TOTAL=0

# new_repo: fresh repo with the script copied in; sets $R.
new_repo() {
  R="$TMP/repo$TOTAL"
  mkdir -p "$R/tools"
  git -C "$R" init -q
  git -C "$R" config user.name test
  git -C "$R" config user.email test@example.invalid
  cp "$SCRIPT" "$R/tools/check-public.sh"
}

# expect <fail|pass> <description> <path> <content>  (file is staged, then checked)
expect() {
  local want="$1" desc="$2" path="$3" content="$4"
  TOTAL=$((TOTAL + 1))
  new_repo
  mkdir -p "$R/$(dirname "$path")"
  printf '%s\n' "$content" > "$R/$path"
  git -C "$R" add "$path"
  local out rc
  out="$(cd "$R" && SILVANUS_DENY_LIST="${DENY:-$TMP/none.txt}" tools/check-public.sh --staged 2>&1)"
  rc=$?
  if { [ "$want" = fail ] && [ $rc -eq 1 ]; } || { [ "$want" = pass ] && [ $rc -eq 0 ]; }; then
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $desc (wanted $want, exit $rc)"
    echo "$out" | sed 's/^/    /'
  fi
}

DENY=""
expect fail "staged .wav" "a.wav" "x"
expect fail "png outside Brand and Icon" "x.png" "x"
expect pass "png in Brand/" "Brand/x.png" "x"
expect pass "png in Icon/" "Icon/x.png" "x"
expect fail "home path in content" "notes.txt" "see ${HOMEDIR}someone/file"
expect fail "automattic address" "notes.txt" "mail someone@automattic.com"
expect fail "a8c address" "notes.txt" "mail someone@a8c.com"
expect pass "clean swift file" "Sources/App.swift" "import Foundation"

printf '# a comment about Fabrikam\n\nContoso\n' > "$TMP/deny.txt"
DENY="$TMP/deny.txt"
expect fail "deny term, case-insensitive" "n.txt" "met with contoso today"
expect pass "deny term must be a whole word" "n.txt" "contosolike is fine"
expect pass "comment lines in list are ignored" "n.txt" "Fabrikam"
expect pass "clean file with deny list" "n.txt" "nothing private here"

# Missing list: warns on stderr but still runs the other checks.
DENY="$TMP/missing.txt"
TOTAL=$((TOTAL + 1))
new_repo
echo x > "$R/a.wav"
git -C "$R" add a.wav
err="$(cd "$R" && SILVANUS_DENY_LIST="$DENY" tools/check-public.sh --staged 2>&1)"
if echo "$err" | grep -qi "deny list" && echo "$err" | grep -q "a.wav"; then PASSED=$((PASSED + 1)); else echo "FAIL: missing deny list should warn and still flag"; fi

# --tree and --history
DENY="$TMP/deny.txt"
TOTAL=$((TOTAL + 1))
new_repo
echo "see ${HOMEDIR}someone/x" > "$R/n.txt"
git -C "$R" add n.txt && git -C "$R" commit -qm one
if (cd "$R" && SILVANUS_DENY_LIST="$DENY" tools/check-public.sh --tree >/dev/null 2>&1); then echo "FAIL: --tree should flag"; else PASSED=$((PASSED + 1)); fi

TOTAL=$((TOTAL + 1))
new_repo
echo "mail a@a8c.com" > "$R/n.txt"
git -C "$R" add n.txt && git -C "$R" commit -qm one
git -C "$R" rm -q n.txt && git -C "$R" commit -qm two
if (cd "$R" && SILVANUS_DENY_LIST="$DENY" tools/check-public.sh --tree >/dev/null 2>&1) \
  && ! (cd "$R" && SILVANUS_DENY_LIST="$DENY" tools/check-public.sh --history >/dev/null 2>&1); then PASSED=$((PASSED + 1)); else echo "FAIL: --history should find deleted blob"; fi

echo "PASS $PASSED/$TOTAL"
[ "$PASSED" -eq "$TOTAL" ]
