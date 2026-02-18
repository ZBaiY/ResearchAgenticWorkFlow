#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

MULTISTEP_CONSTRAINTS_EXAMPLE='MIN_EXAMPLE: assumptions: a>0, x in Reals; limits: time<10s; tools: local symbolic only; network: none'

contains_forbidden_tokens() {
  local text="$1"
  grep -Eqi '(^NEXT(_[A-Z0-9]+)?=|^RUN_COMMAND=|^Next:|^[[:space:]]*\./|^[[:space:]]*bash |I.ll run|\\./bin/agenthub)' <<<"$text"
}

assert_clean_schema_output() {
  local text="$1"
  if grep -Eq '(Explored|Search|Read|functions\.exec_command|to=functions\.exec_command|recipient_name|tool_uses)' <<<"$text"; then
    echo "FAIL: schema output contains debug/noise token"
    exit 1
  fi
  if grep -Eq '(彩票|博彩|娱乐平台|网站)' <<<"$text"; then
    echo "FAIL: schema output contains non-business content"
    exit 1
  fi
  if LC_ALL=C grep -n '[^ -~[:space:]]' <<<"$text" >/dev/null; then
    echo "FAIL: schema output contains non-ASCII bytes"
    exit 1
  fi
}

MOCK_BIN_DIR="$(mktemp -d /tmp/wolfram_mock.XXXXXX)"
cleanup() {
  rm -rf "$MOCK_BIN_DIR"
}
trap cleanup EXIT

cat > "$MOCK_BIN_DIR/wolframscript" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUT="${STEP_OUTPUT_JSON:?}"
cat > "$OUT" <<JSON
{"intent":"mock","status":"ok","message":"","leaf_count":5,"result":"x^2+2 x+1","equivalence_check":"True","spotcheck":"0"}
JSON
echo "mock_wolframscript_ok"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/wolframscript"

echo "[case a] start + prompt chain persistence"
START_OUT="$(./bart "symbolic multistep compute" --skill compute_algebraic_multistep --start)"
printf '%s\n' "$START_OUT"
if contains_forbidden_tokens "$START_OUT"; then
  echo "FAIL: start output contains continuation token"
  exit 1
fi
assert_clean_schema_output "$START_OUT"
grep -q '^REQUEST_STEP=goal$' <<<"$START_OUT" || { echo "FAIL: missing REQUEST_STEP=goal"; exit 1; }
grep -q 'What is the goal of this symbolic multistep computation' <<<"$START_OUT" || {
  echo "FAIL: missing multistep goal prompt"
  exit 1
}

TASK_ID="$(printf '%s\n' "$START_OUT" | sed -n 's/^TASK=\([^ ]*\).*/\1/p' | head -n1)"
[[ -n "$TASK_ID" ]] || { echo "FAIL: unable to parse TASK"; exit 1; }

REQ_JSON="AGENTS/tasks/$TASK_ID/request.json"
[[ -f "$REQ_JSON" ]] || { echo "FAIL: missing request.json"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK_ID/work/src/plan.json" ]] || { echo "FAIL: plan.json must not exist after start"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK_ID/work/report_plan.md" ]] || { echo "FAIL: report_plan.md must not exist after start"; exit 1; }

./bin/agenthub request-set --task "$TASK_ID" --field goal --value "Derive a symbolic simplification pipeline." >/tmp/multi_goal.out
./bin/agenthub request-set --task "$TASK_ID" --field inputs --value '{"expression":"(x^2-1)/(x-1)","variables":{"x":"real"},"assumptions":"x!=1"}' >/tmp/multi_inputs.out
./bin/agenthub request-set --task "$TASK_ID" --field expected_outputs --value '{"symbolic_result":"simplified_expression","verification":"equivalence"}' >/tmp/multi_expected.out
./bin/agenthub request-set --task "$TASK_ID" --field constraints --value '["No internet","Deterministic steps only"]' >/tmp/multi_constraints.out
assert_clean_schema_output "$(cat /tmp/multi_goal.out)"
assert_clean_schema_output "$(cat /tmp/multi_inputs.out)"
assert_clean_schema_output "$(cat /tmp/multi_expected.out)"
assert_clean_schema_output "$(cat /tmp/multi_constraints.out)"
grep -qx "$MULTISTEP_CONSTRAINTS_EXAMPLE" /tmp/multi_expected.out || {
  echo "FAIL: missing multistep constraints MIN_EXAMPLE"
  exit 1
}
if grep -qx "$MULTISTEP_CONSTRAINTS_EXAMPLE" /tmp/multi_goal.out || grep -qx "$MULTISTEP_CONSTRAINTS_EXAMPLE" /tmp/multi_inputs.out || grep -qx "$MULTISTEP_CONSTRAINTS_EXAMPLE" /tmp/multi_constraints.out; then
  echo "FAIL: multistep constraints MIN_EXAMPLE leaked to non-constraints step"
  exit 1
fi
OUT_FMT="$(./bin/agenthub request-set --task "$TASK_ID" --field preferred_formats --value '["json","latex"]')"
printf '%s\n' "$OUT_FMT"
assert_clean_schema_output "$OUT_FMT"
grep -q '^REQUEST_STEP=policy_customize$' <<<"$OUT_FMT" || {
  echo "FAIL: expected policy_customize step after core fields"
  exit 1
}

OUT_P0="$(./bin/agenthub request-set --task "$TASK_ID" --field policy_customize --value yes)"
printf '%s\n' "$OUT_P0"
assert_clean_schema_output "$OUT_P0"
grep -q '^REQUEST_STEP=policy_max_steps$' <<<"$OUT_P0" || { echo "FAIL: expected policy_max_steps"; exit 1; }
./bin/agenthub request-set --task "$TASK_ID" --field policy_max_steps --value 4 >/tmp/multi_p1.out
./bin/agenthub request-set --task "$TASK_ID" --field policy_time_limit_sec_per_step --value 5 >/tmp/multi_p2.out
./bin/agenthub request-set --task "$TASK_ID" --field policy_max_leaf_count --value 100 >/tmp/multi_p3.out
assert_clean_schema_output "$(cat /tmp/multi_p1.out)"
assert_clean_schema_output "$(cat /tmp/multi_p2.out)"
assert_clean_schema_output "$(cat /tmp/multi_p3.out)"
OUT_OVR="$(./bin/agenthub request-set --task "$TASK_ID" --field policy_overrides --value '{"assumptions":"x>0","unknown_key":"ignored","check_level":"equivalence+spotcheck"}')"
printf '%s\n' "$OUT_OVR"
assert_clean_schema_output "$OUT_OVR"
grep -q '^REQUEST_STEP=done$' <<<"$OUT_OVR" || { echo "FAIL: expected done step"; exit 1; }
grep -q '^REQUEST_COMPLETE=true$' <<<"$OUT_OVR" || { echo "FAIL: expected complete request marker"; exit 1; }
grep -q '^STOP_REASON=request_complete_waiting_user_run$' <<<"$OUT_OVR" || { echo "FAIL: expected wait-user-run stop reason"; exit 1; }
if grep -Eq '^(PLAN_STATUS|REVIEW_TOKEN_ISSUED|REVIEW_TOKEN)=' <<<"$OUT_OVR"; then
  echo "FAIL: request-set completion must not emit plan/token markers"
  exit 1
fi
if grep -q 'Say continue to run and I’ll execute it\.' <<<"$OUT_OVR"; then
  echo "FAIL: old completion sentence must not appear"
  exit 1
fi
grep -q '^Say continue and we will start to plan\.$' <<<"$OUT_OVR" || { echo "FAIL: missing updated completion sentence"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK_ID/work/src/plan.json" ]] || { echo "FAIL: plan.json must not exist before explicit run"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK_ID/work/report_plan.md" ]] || { echo "FAIL: report_plan.md must not exist before explicit run"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK_ID/work/out/step_01.json" ]] || { echo "FAIL: execution artifacts created before explicit execute"; exit 1; }

python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$REQ_JSON").read_text(encoding="utf-8"))
assert obj["goal"]
assert isinstance(obj["inputs"], dict) and obj["inputs"]["expression"]
assert isinstance(obj["expected_outputs"], dict)
assert isinstance(obj["constraints"], list) and len(obj["constraints"]) == 2
assert isinstance(obj["preferred_formats"], list) and len(obj["preferred_formats"]) == 2
policy = obj["policy"]
assert policy["max_steps"] == 4
assert policy["time_limit_sec_per_step"] == 5
assert policy["max_leaf_count"] == 100
assert policy["assumptions"] == "x>0"
assert policy["check_level"] == "equivalence+spotcheck"
assert "unknown_key" not in policy
PY

echo "[case b] explicit run generates plan-only and stops for review"
RUN_PLAN_OUT="$(./bin/agenthub run --task "$TASK_ID" --yes </dev/null)"
printf '%s\n' "$RUN_PLAN_OUT"
if contains_forbidden_tokens "$RUN_PLAN_OUT"; then
  echo "FAIL: run output contains continuation token"
  exit 1
fi
assert_clean_schema_output "$RUN_PLAN_OUT"
grep -q '^PLAN_STATUS=READY_FOR_REVIEW$' <<<"$RUN_PLAN_OUT" || { echo "FAIL: missing PLAN_STATUS"; exit 1; }
grep -q '^EXECUTION_ALLOWED=false$' <<<"$RUN_PLAN_OUT" || { echo "FAIL: missing EXECUTION_ALLOWED=false"; exit 1; }
grep -q '^STOP_REASON=need_user_review$' <<<"$RUN_PLAN_OUT" || { echo "FAIL: missing need_user_review stop reason"; exit 1; }
grep -q '^PLAN_PATH=AGENTS/tasks/' <<<"$RUN_PLAN_OUT" || { echo "FAIL: missing plan path marker"; exit 1; }
grep -q '^Review required\.$' <<<"$RUN_PLAN_OUT" || { echo "FAIL: missing plan review guidance"; exit 1; }
grep -Eq '(PROMOTION_STATUS|PROMOTION_PENDING|promote)' <<<"$RUN_PLAN_OUT" && {
  echo "FAIL: plan stage must not mention promotion"
  exit 1
}

PLAN_JSON="AGENTS/tasks/$TASK_ID/work/src/plan.json"
python3 - <<PY
import json
from pathlib import Path
plan = json.loads(Path("$PLAN_JSON").read_text(encoding="utf-8"))
assert isinstance(plan.get("policy"), dict)
assert isinstance(plan.get("steps"), list) and len(plan["steps"]) > 0
for step in plan["steps"]:
    assert {"intent", "wl_code", "expected_form", "check_expr"} <= set(step.keys())
PY

echo "[case c] execute blocked until review-accept"
RUN_EXEC_BLOCKED="$(PATH="$MOCK_BIN_DIR:$PATH" ./bin/agenthub run --task "$TASK_ID" --execute --yes </dev/null)"
printf '%s\n' "$RUN_EXEC_BLOCKED"
assert_clean_schema_output "$RUN_EXEC_BLOCKED"
grep -q '^EXECUTION_ALLOWED=false$' <<<"$RUN_EXEC_BLOCKED" || { echo "FAIL: expected execution blocked marker"; exit 1; }
grep -q '^STOP_REASON=need_user_review$' <<<"$RUN_EXEC_BLOCKED" || { echo "FAIL: expected need_user_review gate"; exit 1; }
grep -q '^REVIEW_READY_FOR_EXECUTE=false$' <<<"$RUN_EXEC_BLOCKED" || { echo "FAIL: expected review latch false marker"; exit 1; }
grep -q '^HINT=Review required\.$' <<<"$RUN_EXEC_BLOCKED" || { echo "FAIL: missing blocked execute review guidance"; exit 1; }
[[ ! -f "AGENTS/tasks/$TASK_ID/work/out/step_01.json" ]] || { echo "FAIL: execute should be blocked before review-accept"; exit 1; }

echo "[case d] review-accept without token fails"
set +e
REVIEW_ACCEPT_MISSING="$(./bin/agenthub review-accept --task "$TASK_ID" 2>&1)"
REVIEW_ACCEPT_MISSING_RC=$?
set -e
printf '%s\n' "$REVIEW_ACCEPT_MISSING"
[[ "$REVIEW_ACCEPT_MISSING_RC" -ne 0 ]] || { echo "FAIL: expected review-accept without token to fail"; exit 1; }

TOKEN_PATH="AGENTS/tasks/$TASK_ID/work/review_token.txt"
[[ -f "$TOKEN_PATH" ]] || { echo "FAIL: missing review token file"; exit 1; }
TOKEN_VALUE="$(tr -d '\r\n' < "$TOKEN_PATH")"
[[ -n "$TOKEN_VALUE" ]] || { echo "FAIL: empty review token"; exit 1; }

echo "[case e] review-accept with valid token enables execute"
REVIEW_ACCEPT_OUT="$(./bin/agenthub review-accept --task "$TASK_ID" --token "$TOKEN_VALUE")"
printf '%s\n' "$REVIEW_ACCEPT_OUT"
grep -q '^REVIEW_ACCEPTED=true$' <<<"$REVIEW_ACCEPT_OUT" || { echo "FAIL: missing review accepted marker"; exit 1; }
grep -q '^REVIEW_READY_FOR_EXECUTE=true$' <<<"$REVIEW_ACCEPT_OUT" || { echo "FAIL: missing review ready marker"; exit 1; }
grep -q '^STOP_REASON=request_complete_waiting_user_execute$' <<<"$REVIEW_ACCEPT_OUT" || { echo "FAIL: missing review-accept stop reason"; exit 1; }

RUN_EXEC_OK="$(PATH="$MOCK_BIN_DIR:$PATH" ./bin/agenthub run --task "$TASK_ID" --execute --yes </dev/null)"
printf '%s\n' "$RUN_EXEC_OK"
assert_clean_schema_output "$RUN_EXEC_OK"
grep -q '^EXECUTION_STATUS=COMPLETED$' <<<"$RUN_EXEC_OK" || { echo "FAIL: execute did not complete"; exit 1; }
[[ -f "AGENTS/tasks/$TASK_ID/work/out/step_01.json" ]] || { echo "FAIL: missing step output"; exit 1; }

echo "[case f] plan-only run resets review latch"
RUN_PLAN_RESET="$(./bin/agenthub run --task "$TASK_ID" --yes </dev/null)"
printf '%s\n' "$RUN_PLAN_RESET"
grep -q '^PLAN_STATUS=READY_FOR_REVIEW$' <<<"$RUN_PLAN_RESET" || { echo "FAIL: missing PLAN_STATUS on reset run"; exit 1; }
grep -q '^STOP_REASON=need_user_review$' <<<"$RUN_PLAN_RESET" || { echo "FAIL: missing need_user_review on reset run"; exit 1; }

RUN_EXEC_REBLOCKED="$(PATH="$MOCK_BIN_DIR:$PATH" ./bin/agenthub run --task "$TASK_ID" --execute --yes </dev/null)"
printf '%s\n' "$RUN_EXEC_REBLOCKED"
grep -q '^EXECUTION_ALLOWED=false$' <<<"$RUN_EXEC_REBLOCKED" || { echo "FAIL: expected execute blocked after plan regeneration"; exit 1; }
grep -q '^REVIEW_READY_FOR_EXECUTE=false$' <<<"$RUN_EXEC_REBLOCKED" || { echo "FAIL: expected review latch reset false"; exit 1; }

NEW_TOKEN="$(tr -d '\r\n' < "$TOKEN_PATH")"
[[ -n "$NEW_TOKEN" ]] || { echo "FAIL: missing regenerated token"; exit 1; }
[[ "$NEW_TOKEN" != "$TOKEN_VALUE" ]] || { echo "FAIL: expected token rotation after plan regeneration"; exit 1; }

set +e
REVIEW_ACCEPT_OLD_TOKEN="$(./bin/agenthub review-accept --task "$TASK_ID" --token "$TOKEN_VALUE" 2>&1)"
REVIEW_ACCEPT_OLD_TOKEN_RC=$?
set -e
printf '%s\n' "$REVIEW_ACCEPT_OLD_TOKEN"
[[ "$REVIEW_ACCEPT_OLD_TOKEN_RC" -ne 0 ]] || { echo "FAIL: old token should be rejected after plan regeneration"; exit 1; }
grep -q '^REVIEW_ACCEPTED=false$' <<<"$REVIEW_ACCEPT_OLD_TOKEN" || { echo "FAIL: expected REVIEW_ACCEPTED=false for old token"; exit 1; }

echo "[case g] execute enforces max_leaf_count policy"
TASK_FAIL="test_compute_multistep_leaffail_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill compute_algebraic_multistep --task-name "$TASK_FAIL" --request AGENTS/skills/compute_algebraic_multistep/templates/request.json.template >/tmp/multi_leaffail_start.out
./bin/agenthub request-set --task "$TASK_FAIL" --field goal --value "Derive a symbolic simplification pipeline." >/tmp/multi_leaffail_goal.out
./bin/agenthub request-set --task "$TASK_FAIL" --field inputs --value '{"expression":"(x^2-1)/(x-1)","variables":{"x":"real"},"assumptions":"x!=1"}' >/tmp/multi_leaffail_inputs.out
./bin/agenthub request-set --task "$TASK_FAIL" --field expected_outputs --value '{"symbolic_result":"simplified_expression"}' >/tmp/multi_leaffail_expected.out
./bin/agenthub request-set --task "$TASK_FAIL" --field constraints --value '["No internet","Deterministic steps only"]' >/tmp/multi_leaffail_constraints.out
./bin/agenthub request-set --task "$TASK_FAIL" --field preferred_formats --value '["json","latex"]' >/tmp/multi_leaffail_formats.out
./bin/agenthub request-set --task "$TASK_FAIL" --field policy_customize --value yes >/tmp/multi_leaffail_policy0.out
./bin/agenthub request-set --task "$TASK_FAIL" --field policy_max_steps --value 4 >/tmp/multi_leaffail_policy1.out
./bin/agenthub request-set --task "$TASK_FAIL" --field policy_time_limit_sec_per_step --value 5 >/tmp/multi_leaffail_policy2.out
./bin/agenthub request-set --task "$TASK_FAIL" --field policy_max_leaf_count --value 1 >/tmp/multi_leaffail_policy3.out
./bin/agenthub request-set --task "$TASK_FAIL" --field policy_overrides --value no >/tmp/multi_leaffail_policy4.out
./bin/agenthub run --task "$TASK_FAIL" --yes >/tmp/multi_leaffail_plan.out
FAIL_TOKEN_PATH="AGENTS/tasks/$TASK_FAIL/work/review_token.txt"
[[ -f "$FAIL_TOKEN_PATH" ]] || { echo "FAIL: missing fail-case review token file"; exit 1; }
FAIL_TOKEN="$(tr -d '\r\n' < "$FAIL_TOKEN_PATH")"
./bin/agenthub review-accept --task "$TASK_FAIL" --token "$FAIL_TOKEN" >/tmp/multi_leaffail_accept.out
set +e
RUN_EXEC_FAIL="$(PATH="$MOCK_BIN_DIR:$PATH" ./bin/agenthub run --task "$TASK_FAIL" --execute --yes </dev/null 2>&1)"
RUN_EXEC_FAIL_RC=$?
set -e
printf '%s\n' "$RUN_EXEC_FAIL"
[[ "$RUN_EXEC_FAIL_RC" -ne 0 ]] || { echo "FAIL: expected execute failure on leaf cap"; exit 1; }
grep -q 'EXECUTION_STATUS=FAILED' <<<"$RUN_EXEC_FAIL" || { echo "FAIL: missing failure execution status"; exit 1; }

echo "[case h] promote purity blocks invalid dst prefixes"
PROMOTE_JSON="GATE/staged/$TASK_ID/PROMOTE.json"
[[ -f "$PROMOTE_JSON" ]] || { echo "FAIL: missing PROMOTE.json"; exit 1; }
python3 - <<PY
import json
from pathlib import Path
p = Path("$PROMOTE_JSON")
obj = json.loads(p.read_text(encoding="utf-8"))
obj["mappings"][0]["dst"] = "USER/not_allowed/path"
p.write_text(json.dumps(obj, indent=2), encoding="utf-8")
PY
set +e
PROM_OUT="$(./bin/agenthub promote --task "$TASK_ID" --yes --allow-user-write-noninteractive 2>&1)"
PROM_RC=$?
set -e
printf '%s\n' "$PROM_OUT"
[[ "$PROM_RC" -ne 0 ]] || { echo "FAIL: expected promote failure for invalid dst prefix"; exit 1; }
grep -q 'PROMOTE_TO_USER=blocked reason=' <<<"$PROM_OUT" || { echo "FAIL: missing blocked reason"; exit 1; }

echo "PASS: compute_algebraic_multistep regression checks passed"
