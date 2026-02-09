#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

assert_contains() {
  local text="$1"
  local pat="$2"
  if ! printf '%s\n' "$text" | rg -q "$pat"; then
    echo "FAIL: missing pattern: $pat" >&2
    exit 1
  fi
}

assert_not_contains() {
  local text="$1"
  local pat="$2"
  if printf '%s\n' "$text" | rg -q "$pat"; then
    echo "FAIL: unexpected pattern: $pat" >&2
    exit 1
  fi
}

OUT="$(./bart "update project meta from draft")"
printf '%s\n' "$OUT"

assert_contains "$OUT" '^Request: update project meta from draft$'
assert_contains "$OUT" '^Mode: '
assert_contains "$OUT" '^Candidates:$'
assert_contains "$OUT" '^\[1\] [a-z0-9_]+  score=[0-9]+\.[0-9]  reasons='
assert_contains "$OUT" '^Pick required: yes$'
assert_contains "$OUT" '^Next:$'
assert_contains "$OUT" '^  \./bart "update project meta from draft" --pick 1 --start$'
assert_contains "$OUT" '^  \./bart "update project meta from draft" --skill [a-z0-9_]+ --start$'
assert_not_contains "$OUT" '^NEXT_1='
assert_not_contains "$OUT" '^NEXT_2='

echo "PASS: bart output snapshot matches human-readable format"
