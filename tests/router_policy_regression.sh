#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! printf '%s\n' "$haystack" | rg -q "$needle"; then
    echo "FAIL: expected pattern '$needle'" >&2
    exit 1
  fi
}

echo "[1/6] draft/meta intent should prioritize paper_profile_update"
OUT1="$(./bart "can you configurate the current project based on the draft we have now?")"
printf '%s\n' "$OUT1"
assert_contains "$OUT1" '^RECOMMENDED_SKILL=paper_profile_update$'
assert_contains "$OUT1" '^MODE=HIGHCONF$'
assert_contains "$OUT1" '  1\) paper_profile_update '
assert_contains "$OUT1" '^PICK_REQUIRED=1$'

echo "[2/6] symbolic intent"
OUT2="$(./bart "derive a symbolic series integral in mathematica")"
printf '%s\n' "$OUT2"
assert_contains "$OUT2" '^RECOMMENDED_SKILL=compute_symbolic$'

echo "[3/6] numerical intent"
OUT3="$(./bart "run a python numeric monte carlo simulation scan and plot")"
printf '%s\n' "$OUT3"
assert_contains "$OUT3" '^RECOMMENDED_SKILL=compute_numerical$'

echo "[4/6] slide intent"
OUT4="$(./bart "prepare a seminar slide deck and presentation flow")"
printf '%s\n' "$OUT4"
assert_contains "$OUT4" '^RECOMMENDED_SKILL=slide_preparation$'

echo "[5/6] low confidence barefoot warning"
OUT5="$(./bart "blorp frobnicate quantum banana unicorn")"
printf '%s\n' "$OUT5"
assert_contains "$OUT5" '^MODE=LOWCONF$'
assert_contains "$OUT5" '^WARN=NO_GOOD_SKILL_MATCH \(barefoot\)$'

echo "[6/6] multi-threshold should list all must_show candidates"
OUT6="$(./bart "from this paper draft, build a seminar slide deck and collect literature references")"
printf '%s\n' "$OUT6"
assert_contains "$OUT6" '^MODE=HIGHCONF$'
assert_contains "$OUT6" 'paper_profile_update'
assert_contains "$OUT6" 'slide_preparation'
assert_contains "$OUT6" 'literature_scout'

echo "PASS: router policy regression checks passed"
