#!/bin/bash
# Keeps private data out of this public repo.
# Usage: tools/check-public.sh [--staged|--tree|--history]   (default --staged)
# Exits 0 when clean; exits 1 and prints one "path: reason" line per finding.
# Deny terms: SILVANUS_DENY_LIST, default $HOME/Projects/silvanus/private/deny-terms.txt.
set -u

MODE="--staged"
case "${1:-}" in
  "") ;;
  --staged|--tree|--history) MODE="$1" ;;
  *) echo "usage: $0 [--staged|--tree|--history]" >&2; exit 2 ;;
esac

DENY_LIST="${SILVANUS_DENY_LIST:-$HOME/Projects/silvanus/private/deny-terms.txt}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TERMS="$WORK/terms"
FINDINGS="$WORK/findings"
: > "$TERMS"
: > "$FINDINGS"

if [ -f "$DENY_LIST" ]; then
  tr -d '\r' < "$DENY_LIST" | grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' > "$TERMS" || true
else
  echo "check-public: warning: deny list not found at $DENY_LIST; skipping deny-term check" >&2
fi

HOME_PREFIX="/Us""ers/"   # split so this file never contains the literal prefix

# These two files must contain the patterns, so they skip the email-domain and deny-term checks.
is_self() {
  case "$1" in tools/check-public.sh|tools/test-check-public.sh) return 0 ;; esac
  return 1
}

report() { echo "$1: $2" >> "$FINDINGS"; }

# check_name <label> <path>
check_name() {
  local label="$1" path="$2" base lower
  base="${path##*/}"
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.caf|*.wav|*.m4a|*.mp3|*.aac) report "$label:$path" "audio file" ;;
    *.p12|*.cer|*.pem|*.key) report "$label:$path" "signing material" ;;
    .env|.env.*|*.env) report "$label:$path" "environment file" ;;
  esac
  case "$lower" in
    *.png|*.jpg|*.jpeg|*.gif|*.heic|*.pdf)
      case "$path" in
        Brand/*|Icon/*) ;;
        *) report "$label:$path" "image or PDF outside Brand/ and Icon/" ;;
      esac ;;
  esac
}

# check_content <label> <path> <file with the content>
check_content() {
  local label="$1" path="$2" file="$3"
  if grep -qIF -e "$HOME_PREFIX" "$file" 2>/dev/null; then
    report "$label:$path" "contains an absolute home path"
  fi
  if is_self "$path"; then return; fi
  if grep -qIiF -e "automattic.com" -e "a8c.com" "$file" 2>/dev/null; then
    report "$label:$path" "contains a work email domain"
  fi
  if [ -s "$TERMS" ] && grep -qIiwF -f "$TERMS" "$file" 2>/dev/null; then
    report "$label:$path" "contains a deny-list term"
  fi
}

case "$MODE" in
  --staged)
    while IFS= read -r -d '' path; do
      check_name "staged" "$path"
      git show ":$path" > "$WORK/blob" 2>/dev/null && check_content "staged" "$path" "$WORK/blob"
    done < <(git diff --cached --name-only --diff-filter=ACMR -z)
    ;;
  --tree)
    while IFS= read -r -d '' path; do
      check_name "tree" "$path"
      [ -f "$path" ] && check_content "tree" "$path" "$path"
    done < <(git ls-files -z)
    ;;
  --history)
    while read -r sha path; do
      [ -n "$path" ] || continue
      [ "$(git cat-file -t "$sha" 2>/dev/null)" = blob ] || continue
      short="$(git rev-parse --short "$sha")"
      check_name "$short" "$path"
      git cat-file blob "$sha" > "$WORK/blob" && check_content "$short" "$path" "$WORK/blob"
    done < <(git rev-list --all --objects)
    ;;
esac

if [ -s "$FINDINGS" ]; then
  sort -u "$FINDINGS"
  exit 1
fi
exit 0
