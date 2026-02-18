#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REQ="regression stop-after-run $(date -u +%Y%m%dT%H%M%SZ)"

contains() {
  local haystack="$1"
  local needle="$2"
  grep -Fq -- "$needle" <<<"$haystack"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if contains "$haystack" "$needle"; then
    echo "FAIL: unexpected output contains: $needle" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! contains "$haystack" "$needle"; then
    echo "FAIL: expected output missing: $needle" >&2
    exit 1
  fi
}

START_OUT="$("$ROOT/bart" "$REQ" --skill paper_profile_update --start 2>&1)"
assert_not_contains "$START_OUT" "Interacted with background terminal"
assert_not_contains "$START_OUT" "(waited)"
assert_not_contains "$START_OUT" "RUN_PENDING=true"
assert_not_contains "$START_OUT" "RUN_TASK="
assert_not_contains "$START_OUT" "./bin/agenthub run"
assert_not_contains "$START_OUT" "./bin/agenthub promote"
assert_not_contains "$START_OUT" "PROMOTION_PENDING"
assert_contains "$START_OUT" "STATE=AWAITING_USER_CONFIRMATION"

TASK_ID="$(printf '%s\n' "$START_OUT" | sed -n 's/^TASK=\([^ ]*\).*/\1/p' | head -n 1)"
if [[ -z "$TASK_ID" ]]; then
  echo "FAIL: unable to parse TASK from bart --start output" >&2
  exit 1
fi

if [[ -d "$ROOT/GATE/staged/$TASK_ID" ]]; then
  echo "FAIL: start path unexpectedly created staged outputs (auto-run likely happened)" >&2
  exit 1
fi

RUN_OUT="$("$ROOT/bin/agenthub" run --task "$TASK_ID" --no 2>&1)"
assert_not_contains "$RUN_OUT" "Interacted with background terminal"
assert_not_contains "$RUN_OUT" "(waited)"
assert_not_contains "$RUN_OUT" "PROMOTE_TO_USER=done"
assert_not_contains "$RUN_OUT" "--allow-user-write-noninteractive"
assert_contains "$RUN_OUT" "PROMOTION_PENDING: true"
assert_contains "$RUN_OUT" "Run completed. Inspect GATE output. I will promote only when you say READY."

if compgen -G "$ROOT/USER/manifest/promotion_receipts/${TASK_ID}_*.json" >/dev/null; then
  echo "FAIL: run path unexpectedly wrote promotion receipt (auto-promote happened)" >&2
  exit 1
fi

echo "REGRESSION=ok stop_after_run task=$TASK_ID"
