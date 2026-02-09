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
  if printf '%s\n' "$text" | rg -qi "$pat"; then
    echo "FAIL: forbidden pattern present: $pat" >&2
    exit 1
  fi
}

before="$(git status --porcelain)"
OUT="$(./bart "can you configurate the current project keywards for initialization?")"
after="$(git status --porcelain)"

echo "[default output]"
printf '%s\n' "$OUT"

assert_contains "$OUT" '^Request: '
assert_contains "$OUT" '^Mode: '
assert_contains "$OUT" '^Candidates:$'
assert_contains "$OUT" '^\[1\] '
assert_contains "$OUT" '^Pick required: yes$'
assert_contains "$OUT" '^Next:$'
assert_contains "$OUT" '^  \./bart ".*" --pick 1 --start$'
assert_contains "$OUT" '^  \./bart ".*" --skill .* --start$'
assert_not_contains "$OUT" 'Explored|patching|running tests|modified|editing'

if [[ "$before" != "$after" ]]; then
  echo "FAIL: default ./bart changed repo state" >&2
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
  exit 1
fi

OUT_LOW="$(./bart "blorp frobnicate quantum banana unicorn")"
echo "[lowconf output]"
printf '%s\n' "$OUT_LOW"
assert_contains "$OUT_LOW" '^Mode: LOWCONF \(score='
assert_contains "$OUT_LOW" '^WARNING: no suitable skill match \(barefoot\)\. Consider rephrasing or using --skill\.$'
assert_contains "$OUT_LOW" '^Pick required: yes$'

OUT_MULTI="$(./bart "from this paper draft, build a seminar slide deck and collect literature references")"
echo "[multi output]"
printf '%s\n' "$OUT_MULTI"
assert_contains "$OUT_MULTI" 'paper_profile_update'
assert_contains "$OUT_MULTI" 'slide_preparation'
assert_contains "$OUT_MULTI" 'literature_scout'
assert_contains "$OUT_MULTI" '^Pick required: yes$'

echo "PASS: bart suggest-only and policy regression checks passed"
