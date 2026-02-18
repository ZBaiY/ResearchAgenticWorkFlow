#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

./bin/agenthub index >/tmp/compute_matcher_index.out

assert_top1() {
  local query="$1"
  local expected="$2"
  local out
  out="$(./bart "$query")"
  printf '%s\n' "$out"

  local top1
  top1="$(printf '%s\n' "$out" | sed -n 's/^\[[0-9][0-9]*\] \([^ ]*\).*/\1/p' | head -n1)"
  [[ "$top1" == "$expected" ]] || {
    echo "FAIL: top-1 mismatch for query '$query' expected '$expected' got '$top1'"
    exit 1
  }

  if grep -q '^Mode: LOWCONF' <<<"$out"; then
    echo "FAIL: query '$query' should not be LOWCONF"
    exit 1
  fi

  if grep -Eq 'reasons=.*match:(i|to|want|me|please)(,|$)' <<<"$out"; then
    echo "FAIL: query '$query' leaked stopword match reasons"
    exit 1
  fi

  if grep -Eq '^\[[0-9]+\] compute([[:space:]]|$)' <<<"$out"; then
    echo "FAIL: deprecated skill 'compute' appeared in candidates"
    exit 1
  fi
}

echo "[case a] compute algebraically -> compute_algebraic top-1"
assert_top1 "I want to compute algebraically" "compute_algebraic"

echo "[case b] compute symbolically -> compute_algebraic top-1"
assert_top1 "Please compute symbolically" "compute_algebraic"

echo "[case c] compute numerically -> compute_numerical top-1"
assert_top1 "Can you compute numerically" "compute_numerical"

echo "PASS: compute matcher routing checks passed"
