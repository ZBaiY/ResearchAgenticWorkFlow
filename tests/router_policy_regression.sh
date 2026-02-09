#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! printf '%s\n' "$haystack" | rg -q -- "$needle"; then
    echo "FAIL: expected pattern '$needle'" >&2
    exit 1
  fi
}

echo "[0/7] help output includes key UX flags"
HELP_OUT="$(./bart --help)"
printf '%s\n' "$HELP_OUT"
assert_contains "$HELP_OUT" '--pick'
assert_contains "$HELP_OUT" '--start'
assert_contains "$HELP_OUT" '--run'
assert_contains "$HELP_OUT" '--full-agent'

echo "[1/7] typo-heavy draft/meta intent should prioritize paper_profile_update"
OUT1="$(./bart "configurate current draft keywards initialization for the paper")"
printf '%s\n' "$OUT1"
assert_contains "$OUT1" '^Mode: HIGHCONF \(score='
assert_contains "$OUT1" '^\[1\] paper_profile_update  score='
assert_contains "$OUT1" '^Pick required: yes$'

echo "[2/7] symbolic intent"
OUT2="$(./bart "derive a symbolic series integral in mathematica")"
printf '%s\n' "$OUT2"
assert_contains "$OUT2" '^\[1\] compute_symbolic  score='

echo "[3/7] numerical intent"
OUT3="$(./bart "run a python numeric monte carlo simulation scan and plot")"
printf '%s\n' "$OUT3"
assert_contains "$OUT3" '^\[1\] compute_numerical  score='

echo "[4/7] slide intent"
OUT4="$(./bart "prepare a seminar slide deck and presentation flow")"
printf '%s\n' "$OUT4"
assert_contains "$OUT4" '^\[1\] slide_preparation  score='

echo "[5/7] low confidence barefoot warning"
OUT5="$(./bart "blorp frobnicate quantum banana unicorn")"
printf '%s\n' "$OUT5"
assert_contains "$OUT5" '^Mode: LOWCONF \(score='
assert_contains "$OUT5" '^WARNING: no suitable skill match \(barefoot\)\. Consider rephrasing or using --skill\.$'

echo "[6/7] multi-threshold should list all must_show candidates"
OUT6="$(./bart "from this paper draft, build a seminar slide deck and collect literature references")"
printf '%s\n' "$OUT6"
assert_contains "$OUT6" '^Mode: HIGHCONF \(score='
assert_contains "$OUT6" 'paper_profile_update'
assert_contains "$OUT6" 'slide_preparation'
assert_contains "$OUT6" 'literature_scout'

echo "[7/7] informal pick parsing forms should work"
OUT_PICK1="$(./bart "update the metadata for our project" --pick pick1)"
printf '%s\n' "$OUT_PICK1"
assert_contains "$OUT_PICK1" '^Selected skill: '
assert_contains "$OUT_PICK1" '^Task name: '

OUT_PICK2="$(./bart "update the metadata for our project" --pick "candidate1")"
printf '%s\n' "$OUT_PICK2"
assert_contains "$OUT_PICK2" '^Selected skill: '

OUT_PICK3="$(./bart "update the metadata for our project" --pick "i choose 1")"
printf '%s\n' "$OUT_PICK3"
assert_contains "$OUT_PICK3" '^Selected skill: '

echo "PASS: router policy regression checks passed"
