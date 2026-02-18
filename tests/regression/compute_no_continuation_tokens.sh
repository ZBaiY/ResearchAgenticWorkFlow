#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

contains_forbidden_tokens() {
  local text="$1"
  grep -Eq '(^NEXT(_[A-Z0-9]+)?=|^RUN_COMMAND=|^Next:|^[[:space:]]*\./|^[[:space:]]*bash )' <<<"$text"
}

echo "[case a] bart --start emits no continuation command hints"
START_OUT="$(./bart "numerical compute demo" --skill compute_numerical --start)"
printf '%s\n' "$START_OUT"
if contains_forbidden_tokens "$START_OUT"; then
  echo "FAIL: start output contains continuation token or runnable command"
  exit 1
fi
grep -Eq '^RUN_PENDING=true$|^STATE=AWAITING_USER_CONFIRMATION$' <<<"$START_OUT" || {
  grep -Eq '^REQUEST_COMPLETE=false$|^REQUEST_STEP=goal$' <<<"$START_OUT" || {
    echo "FAIL: missing non-executable start state marker"
    exit 1
  }
}
if ! grep -Eq '^RUN_PENDING=true$|^STATE=AWAITING_USER_CONFIRMATION$|^REQUEST_COMPLETE=false$' <<<"$START_OUT"; then
  echo "FAIL: missing non-executable start state marker"
  exit 1
fi

TASK_ID="$(printf '%s\n' "$START_OUT" | sed -n 's/^TASK=\([^ ]*\).*/\1/p' | head -n1)"
[[ -n "$TASK_ID" ]] || { echo "FAIL: unable to parse TASK from start output"; exit 1; }

./bin/agenthub request-set --task "$TASK_ID" --field goal --value "numerical compute demo" >/tmp/compute_no_token_goal.out
./bin/agenthub request-set --task "$TASK_ID" --field inputs --value '{"mode":"quadratic_scan","x_values":[0,1,2],"coefficients":{"a":1.0,"b":0.0,"c":0.0},"make_plot":false}' >/tmp/compute_no_token_inputs.out
./bin/agenthub request-set --task "$TASK_ID" --field expected_outputs --value '{"result_file":"result.json"}' >/tmp/compute_no_token_expected.out
./bin/agenthub request-set --task "$TASK_ID" --field constraints --value '["No internet access"]' >/tmp/compute_no_token_constraints.out
./bin/agenthub request-set --task "$TASK_ID" --field preferred_formats --value '["json"]' >/tmp/compute_no_token_formats.out

echo "[case b] run emits no continuation command hints"
RUN_OUT="$(./bin/agenthub run --task "$TASK_ID" --yes </dev/null)"
printf '%s\n' "$RUN_OUT"
if contains_forbidden_tokens "$RUN_OUT"; then
  echo "FAIL: run output contains continuation token or runnable command"
  exit 1
fi
grep -q '^PROMOTION_STATUS=READY$' <<<"$RUN_OUT" || { echo "FAIL: missing PROMOTION_STATUS=READY"; exit 1; }

echo "[case c] promote skip emits no continuation command hints"
PROM_OUT="$(./bin/agenthub promote --task "$TASK_ID" --yes </dev/null)"
printf '%s\n' "$PROM_OUT"
if contains_forbidden_tokens "$PROM_OUT"; then
  echo "FAIL: promote output contains continuation token or runnable command"
  exit 1
fi
grep -q '^PROMOTE_TO_USER=skipped reason=noninteractive_requires_explicit_flags$' <<<"$PROM_OUT" || {
  echo "FAIL: missing expected noninteractive skip message"
  exit 1
}

echo "PASS: compute flow has no continuation tokens"
