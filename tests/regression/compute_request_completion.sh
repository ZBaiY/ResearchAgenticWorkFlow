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

TASK="test_compute_request_completion_$(date -u +%Y%m%dT%H%M%SZ)"
START_OUT="$(./bin/agenthub start --skill compute_numerical --task-name "$TASK" --request AGENTS/skills/compute_numerical/templates/request.md)"
printf '%s\n' "$START_OUT"
if contains_forbidden_tokens "$START_OUT"; then
  echo "FAIL: start output contains continuation tokens"
  exit 1
fi
grep -q '^REQUEST_STEP=goal$' <<<"$START_OUT" || { echo "FAIL: expected REQUEST_STEP=goal"; exit 1; }
grep -q '^REQUEST_COMPLETE=false$' <<<"$START_OUT" || { echo "FAIL: expected REQUEST_COMPLETE=false"; exit 1; }
grep -q '^STOP_REASON=need_user_input$' <<<"$START_OUT" || { echo "FAIL: expected STOP_REASON=need_user_input"; exit 1; }
assert_single_min_example "$START_OUT"

REQ_JSON="AGENTS/tasks/$TASK/request.json"
REQ_PROGRESS="AGENTS/tasks/$TASK/request_progress.json"
[[ -f "$REQ_JSON" ]] || { echo "FAIL: missing request.json"; exit 1; }
[[ -f "$REQ_PROGRESS" ]] || { echo "FAIL: missing request_progress.json"; exit 1; }

python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$REQ_JSON").read_text(encoding="utf-8"))
assert obj["goal"] == ""
assert obj["inputs"] == {}
assert obj["expected_outputs"] == {}
assert obj["constraints"] == []
assert obj["preferred_formats"] == []
prog = json.loads(Path("$REQ_PROGRESS").read_text(encoding="utf-8"))
assert prog["current_step"] == "goal"
PY

echo "[step order enforcement]"
set +e
OUT_BAD_STEP="$(./bin/agenthub request-set --task "$TASK" --field constraints --value '["No internet access"]' 2>&1)"
BAD_STEP_RC=$?
set -e
printf '%s\n' "$OUT_BAD_STEP"
[[ "$BAD_STEP_RC" -ne 0 ]] || { echo "FAIL: expected nonzero when updating out-of-order field"; exit 1; }
grep -q "Expected field 'goal' next" <<<"$OUT_BAD_STEP" || { echo "FAIL: expected strict next-field error"; exit 1; }

echo "[step] goal"
OUT_GOAL="$(./bin/agenthub request-set --task "$TASK" --field goal --value "Compute a quadratic scan summary")"
printf '%s\n' "$OUT_GOAL"
if contains_forbidden_tokens "$OUT_GOAL"; then
  echo "FAIL: request-set output contains continuation tokens"
  exit 1
fi
if contains_forbidden_hints "$OUT_GOAL"; then
  echo "FAIL: request-set output contains runnable hint"
  exit 1
fi
grep -q '^REQUEST_STEP=inputs$' <<<"$OUT_GOAL" || { echo "FAIL: expected next step inputs"; exit 1; }
grep -q '^REQUEST_COMPLETE=false$' <<<"$OUT_GOAL" || { echo "FAIL: expected incomplete request"; exit 1; }
grep -q '^STOP_REASON=need_user_input$' <<<"$OUT_GOAL" || { echo "FAIL: expected STOP_REASON=need_user_input"; exit 1; }
assert_single_min_example "$OUT_GOAL"
python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$REQ_JSON").read_text(encoding="utf-8"))
assert obj["goal"] == "Compute a quadratic scan summary"
assert obj["inputs"] == {}
assert obj["expected_outputs"] == {}
assert obj["constraints"] == []
assert obj["preferred_formats"] == []
PY

echo "[step] inputs"
cat > /tmp/compute_inputs_${TASK}.json <<'EOF'
{
  "mode": "quadratic_scan",
  "x_values": [0, 1, 2, 3],
  "coefficients": {"a": 1.0, "b": 2.0, "c": 3.0},
  "make_plot": false
}
EOF
OUT_INPUTS="$(./bin/agenthub request-set --task "$TASK" --field inputs --file /tmp/compute_inputs_${TASK}.json)"
printf '%s\n' "$OUT_INPUTS"
if contains_forbidden_tokens "$OUT_INPUTS"; then
  echo "FAIL: request-set output contains continuation tokens"
  exit 1
fi
if contains_forbidden_hints "$OUT_INPUTS"; then
  echo "FAIL: request-set output contains runnable hint"
  exit 1
fi
grep -q '^REQUEST_STEP=expected_outputs$' <<<"$OUT_INPUTS" || { echo "FAIL: expected next step expected_outputs"; exit 1; }
grep -q '^REQUEST_COMPLETE=false$' <<<"$OUT_INPUTS" || { echo "FAIL: expected incomplete request"; exit 1; }
grep -q '^STOP_REASON=need_user_input$' <<<"$OUT_INPUTS" || { echo "FAIL: expected STOP_REASON=need_user_input"; exit 1; }
assert_single_min_example "$OUT_INPUTS"

echo "[step] expected_outputs"
OUT_EXPECTED="$(./bin/agenthub request-set --task "$TASK" --field expected_outputs --value '{"result_file":"result.json","summary":"mean/min/max"}')"
printf '%s\n' "$OUT_EXPECTED"
if contains_forbidden_tokens "$OUT_EXPECTED"; then
  echo "FAIL: request-set output contains continuation tokens"
  exit 1
fi
if contains_forbidden_hints "$OUT_EXPECTED"; then
  echo "FAIL: request-set output contains runnable hint"
  exit 1
fi
grep -q '^REQUEST_STEP=constraints$' <<<"$OUT_EXPECTED" || { echo "FAIL: expected next step constraints"; exit 1; }
grep -q '^REQUEST_COMPLETE=false$' <<<"$OUT_EXPECTED" || { echo "FAIL: expected incomplete request"; exit 1; }
grep -q '^STOP_REASON=need_user_input$' <<<"$OUT_EXPECTED" || { echo "FAIL: expected STOP_REASON=need_user_input"; exit 1; }
assert_single_min_example "$OUT_EXPECTED"

echo "[step] constraints"
OUT_CONS="$(./bin/agenthub request-set --task "$TASK" --field constraints --value '["No internet access","Keep runtime < 10s"]')"
printf '%s\n' "$OUT_CONS"
if contains_forbidden_tokens "$OUT_CONS"; then
  echo "FAIL: request-set output contains continuation tokens"
  exit 1
fi
if contains_forbidden_hints "$OUT_CONS"; then
  echo "FAIL: request-set output contains runnable hint"
  exit 1
fi
grep -q '^REQUEST_STEP=preferred_formats$' <<<"$OUT_CONS" || { echo "FAIL: expected next step preferred_formats"; exit 1; }
grep -q '^REQUEST_COMPLETE=false$' <<<"$OUT_CONS" || { echo "FAIL: expected incomplete request"; exit 1; }
grep -q '^STOP_REASON=need_user_input$' <<<"$OUT_CONS" || { echo "FAIL: expected STOP_REASON=need_user_input"; exit 1; }
assert_single_min_example "$OUT_CONS"

echo "[step] preferred_formats"
OUT_FMT="$(./bin/agenthub request-set --task "$TASK" --field preferred_formats --value '["json","plain text"]')"
printf '%s\n' "$OUT_FMT"
if contains_forbidden_tokens "$OUT_FMT"; then
  echo "FAIL: request-set output contains continuation tokens"
  exit 1
fi
if contains_forbidden_hints "$OUT_FMT"; then
  echo "FAIL: request-set output contains runnable hint"
  exit 1
fi
grep -q '^REQUEST_STEP=done$' <<<"$OUT_FMT" || { echo "FAIL: expected done step"; exit 1; }
grep -q '^REQUEST_COMPLETE=true$' <<<"$OUT_FMT" || { echo "FAIL: expected complete request"; exit 1; }
grep -q '^STOP_REASON=request_complete_waiting_user_run$' <<<"$OUT_FMT" || { echo "FAIL: expected request_complete stop reason"; exit 1; }
if grep -q '^MIN_EXAMPLE: ' <<<"$OUT_FMT"; then
  echo "FAIL: done state must not emit MIN_EXAMPLE"
  exit 1
fi
[[ ! -f "AGENTS/tasks/$TASK/work/report.md" ]] || { echo "FAIL: run artifacts should not exist before explicit run"; exit 1; }

python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$REQ_JSON").read_text(encoding="utf-8"))
assert obj["goal"] == "Compute a quadratic scan summary"
assert isinstance(obj["inputs"], dict) and obj["inputs"]["mode"] == "quadratic_scan"
assert isinstance(obj["expected_outputs"], dict) and obj["expected_outputs"]["result_file"] == "result.json"
assert isinstance(obj["constraints"], list) and len(obj["constraints"]) == 2
assert isinstance(obj["preferred_formats"], list) and len(obj["preferred_formats"]) == 2
prog = json.loads(Path("$REQ_PROGRESS").read_text(encoding="utf-8"))
assert prog["current_step"] == "done"
PY

echo "[incomplete run check]"
TASK2="test_compute_request_incomplete_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill compute_numerical --task-name "$TASK2" --request AGENTS/skills/compute_numerical/templates/request.md >/tmp/compute_req_incomplete_start.out
RUN_INCOMPLETE_OUT="$(./bin/agenthub run --task "$TASK2" --yes </dev/null)"
printf '%s\n' "$RUN_INCOMPLETE_OUT"
grep -q '^RUN_STATUS=PAUSED_FOR_INPUT$' <<<"$RUN_INCOMPLETE_OUT" || { echo "FAIL: expected paused-for-input status"; exit 1; }
grep -q '^REQUEST_COMPLETE=false$' <<<"$RUN_INCOMPLETE_OUT" || { echo "FAIL: expected incomplete request marker"; exit 1; }
grep -q '^REQUEST_STEP=goal$' <<<"$RUN_INCOMPLETE_OUT" || { echo "FAIL: expected REQUEST_STEP=goal"; exit 1; }
grep -q '^STOP_REASON=need_user_input$' <<<"$RUN_INCOMPLETE_OUT" || { echo "FAIL: expected STOP_REASON=need_user_input"; exit 1; }
assert_single_min_example "$RUN_INCOMPLETE_OUT"
[[ -f "AGENTS/tasks/$TASK2/review/need_input.md" ]] || { echo "FAIL: expected need_input.md for incomplete request"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK2/review/error.md" ]] || { echo "FAIL: should not emit error.md for incomplete request"; exit 1; }

echo "PASS: compute request completion flow checks passed"
