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

snapshot_tasks() {
  find AGENTS/tasks -mindepth 1 -maxdepth 1 -type d -print | sort
}

echo "[1/3] non-full-agent remains suggest-only with pick required"
before_tasks="$(snapshot_tasks)"
OUT1="$(./bart "update project meta from draft")"
after_tasks="$(snapshot_tasks)"
printf '%s\n' "$OUT1"
assert_contains "$OUT1" '^PICK_REQUIRED=1$'
if [[ "$before_tasks" != "$after_tasks" ]]; then
  echo "FAIL: default mode should not create tasks" >&2
  exit 1
fi

echo "[2/3] full-agent auto start/run succeeds non-interactively"
OUT2="$(./bart --full-agent "update project meta from draft" < /dev/null)"
printf '%s\n' "$OUT2"
assert_contains "$OUT2" '^MODE=FULL_AGENT$'
assert_contains "$OUT2" '^RUN=ok$'
assert_contains "$OUT2" '^STAGED_TO_GATE=no$'

TASK2="$(printf '%s\n' "$OUT2" | sed -n 's/^TASK=//p' | head -n1)"
if [[ -z "$TASK2" ]]; then
  echo "FAIL: missing TASK in full-agent output" >&2
  exit 1
fi

if [[ ! -d "AGENTS/tasks/$TASK2" ]]; then
  echo "FAIL: missing task dir AGENTS/tasks/$TASK2" >&2
  exit 1
fi

if [[ -z "$(find "AGENTS/tasks/$TASK2/review" -maxdepth 1 -type f -name '*.md' -print -quit)" ]]; then
  echo "FAIL: expected review report in AGENTS/tasks/$TASK2/review/" >&2
  exit 1
fi

if printf '%s\n' "$OUT2" | rg -q 'Proceed with run\?|EOFError'; then
  echo "FAIL: unexpected interactive prompt markers in full-agent output" >&2
  exit 1
fi

echo "[3/3] low-confidence full-agent still runs with risk marker"
OUT3="$(./bart --full-agent "do something totally unrelated blahblah" < /dev/null)"
printf '%s\n' "$OUT3"
assert_contains "$OUT3" '^MODE=FULL_AGENT$'
assert_contains "$OUT3" '^WARN=NO_GOOD_SKILL_MATCH \(barefoot\)$'
assert_contains "$OUT3" '^RISK=HIGH$'

TASK3="$(printf '%s\n' "$OUT3" | sed -n 's/^TASK=//p' | head -n1)"
if [[ -z "$TASK3" || ! -d "AGENTS/tasks/$TASK3" ]]; then
  echo "FAIL: low-confidence full-agent did not create task" >&2
  exit 1
fi

echo "PASS: full-agent autopilot regression checks passed"
