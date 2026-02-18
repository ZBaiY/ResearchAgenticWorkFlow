#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

contains_forbidden_tokens() {
  local text="$1"
  grep -Eq '(^NEXT(_[A-Z0-9]+)?=|^RUN_COMMAND=|^Next:|^[[:space:]]*\./|^[[:space:]]*bash )' <<<"$text"
}

contains_forbidden_hints() {
  local text="$1"
  grep -Eqi '(^NEXT(_[A-Z0-9]+)?=|^RUN_COMMAND=|^RUN_PENDING=|--run|run now|execute|^[[:space:]]*bash |^[[:space:]]*\./)' <<<"$text"
}

contains_exploration_noise() {
  local text="$1"
  grep -Eqi '(Explored|Search|\\brg\\b|\\bsed\\b|\\bls\\b|\\bcat\\b|--help)' <<<"$text"
}

assert_single_min_example() {
  local text="$1"
  local count
  count="$(grep -c '^MIN_EXAMPLE: ' <<<"$text" || true)"
  [[ "$count" -eq 1 ]] || { echo "FAIL: expected exactly one MIN_EXAMPLE line"; exit 1; }
  local line
  line="$(grep '^MIN_EXAMPLE: ' <<<"$text" | head -n1)"
  [[ ${#line} -le 120 ]] || { echo "FAIL: MIN_EXAMPLE exceeds 120 chars"; exit 1; }
  if grep -Eqi '(\\./|bash|agenthub|NEXT_|RUN_COMMAND|PROMOTE|EXECUTE|\\brun\\b|\\bexecute\\b|\\bstart\\b|\\bpromote\\b)' <<<"$line"; then
    echo "FAIL: MIN_EXAMPLE contains forbidden token"
    exit 1
  fi
}

echo "[case a] bart --pick enters schema mode and stops"
PICK_OUT="$(./bart "I want to compute algebraically" --pick 1)"
printf '%s\n' "$PICK_OUT"
grep -q '^SELECTED_SKILL=compute_algebraic_multistep$' <<<"$PICK_OUT" || { echo "FAIL: missing SELECTED_SKILL marker"; exit 1; }
grep -q '^TASK=' <<<"$PICK_OUT" || { echo "FAIL: missing started TASK marker"; exit 1; }
grep -q '^REQUEST_COMPLETE=false$' <<<"$PICK_OUT" || { echo "FAIL: expected REQUEST_COMPLETE=false"; exit 1; }
grep -q '^REQUEST_STEP=goal$' <<<"$PICK_OUT" || { echo "FAIL: expected REQUEST_STEP=goal"; exit 1; }
grep -q '^STOP_REASON=need_user_input$' <<<"$PICK_OUT" || { echo "FAIL: expected STOP_REASON=need_user_input"; exit 1; }
assert_single_min_example "$PICK_OUT"
if grep -q '^RUN_PENDING=true$' <<<"$PICK_OUT"; then
  echo "FAIL: pick output should not include RUN_PENDING=true"
  exit 1
fi
if contains_forbidden_tokens "$PICK_OUT"; then
  echo "FAIL: pick output contains forbidden continuation token"
  exit 1
fi
if contains_forbidden_hints "$PICK_OUT"; then
  echo "FAIL: pick output contains runnable hint"
  exit 1
fi
if contains_exploration_noise "$PICK_OUT"; then
  echo "FAIL: pick output contains exploration noise"
  exit 1
fi
TASK_ID_PICK="$(printf '%s\n' "$PICK_OUT" | sed -n 's/^TASK=\([^ ]*\).*/\1/p' | head -n1)"
[[ -n "$TASK_ID_PICK" ]] || { echo "FAIL: unable to parse TASK from pick output"; exit 1; }
python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("AGENTS/tasks/$TASK_ID_PICK/request.json").read_text(encoding="utf-8"))
assert obj.get("goal", "") == ""
assert obj.get("inputs", {}) == {}
assert obj.get("expected_outputs", {}) == {}
assert obj.get("constraints", []) == []
assert obj.get("preferred_formats", []) == []
PY
if grep -q '^REQUEST_FIELD_UPDATED=goal$' <<<"$PICK_OUT"; then
  echo "FAIL: pick/start must not prefill goal"
  exit 1
fi

echo "[case b] bart --pick --run pauses on incomplete compute request"
RUN_OUT="$(./bart "I want to compute algebraically" --skill compute_algebraic --run)"
printf '%s\n' "$RUN_OUT"
if contains_forbidden_tokens "$RUN_OUT"; then
  echo "FAIL: bart --run output contains forbidden continuation token"
  exit 1
fi
grep -q '^STARTED=true$' <<<"$RUN_OUT" || { echo "FAIL: expected STARTED=true"; exit 1; }
grep -q '^REQUEST_COMPLETE=false$' <<<"$RUN_OUT" || { echo "FAIL: expected REQUEST_COMPLETE=false"; exit 1; }
grep -q '^REQUEST_STEP=goal$' <<<"$RUN_OUT" || { echo "FAIL: expected REQUEST_STEP=goal"; exit 1; }
grep -q '^STOP_REASON=need_user_input$' <<<"$RUN_OUT" || { echo "FAIL: expected STOP_REASON=need_user_input"; exit 1; }
assert_single_min_example "$RUN_OUT"
if contains_exploration_noise "$RUN_OUT"; then
  echo "FAIL: bart --run schema pause output contains exploration noise"
  exit 1
fi
TASK_ID="$(printf '%s\n' "$RUN_OUT" | sed -n 's/^TASK=\([^ ]*\).*/\1/p' | head -n1)"
[[ -n "$TASK_ID" ]] || { echo "FAIL: unable to parse TASK from bart --run output"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK_ID/review/error.md" ]] || { echo "FAIL: should not create error.md for schema pause"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK_ID/work/report.md" ]] || { echo "FAIL: skill subprocess should not run for incomplete schema"; exit 1; }

echo "[case c] agenthub run pauses before skill subprocess when incomplete"
TASK2="test_compute_gate_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill compute_numerical --task-name "$TASK2" --request AGENTS/skills/compute_numerical/templates/request.md >/tmp/compute_gate_start.out
AGENTHUB_OUT="$(./bin/agenthub run --task "$TASK2" --yes </dev/null)"
printf '%s\n' "$AGENTHUB_OUT"
grep -q '^RUN_STATUS=PAUSED_FOR_INPUT$' <<<"$AGENTHUB_OUT" || { echo "FAIL: missing RUN_STATUS=PAUSED_FOR_INPUT"; exit 1; }
grep -q '^REQUEST_COMPLETE=false$' <<<"$AGENTHUB_OUT" || { echo "FAIL: missing REQUEST_COMPLETE=false"; exit 1; }
grep -q '^REQUEST_STEP=goal$' <<<"$AGENTHUB_OUT" || { echo "FAIL: missing REQUEST_STEP=goal"; exit 1; }
grep -q '^NEED_INPUT_PATH=AGENTS/tasks/' <<<"$AGENTHUB_OUT" || { echo "FAIL: missing NEED_INPUT_PATH marker"; exit 1; }
grep -q '^STOP_REASON=need_user_input$' <<<"$AGENTHUB_OUT" || { echo "FAIL: missing STOP_REASON=need_user_input"; exit 1; }
assert_single_min_example "$AGENTHUB_OUT"
[[ -f "AGENTS/tasks/$TASK2/review/need_input.md" ]] || { echo "FAIL: missing need_input.md"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK2/review/error.md" ]] || { echo "FAIL: should not emit error.md"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK2/work/report.md" ]] || { echo "FAIL: skill subprocess should not run while request incomplete"; exit 1; }
if contains_forbidden_tokens "$AGENTHUB_OUT"; then
  echo "FAIL: agenthub paused output contains forbidden token"
  exit 1
fi
if contains_exploration_noise "$AGENTHUB_OUT"; then
  echo "FAIL: agenthub schema pause output contains exploration noise"
  exit 1
fi

echo "PASS: compute run gate behavior checks passed"
