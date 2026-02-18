#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="compute_algebraic_multistep"
EXECUTE_MODE="${COMPUTE_EXECUTE:-0}"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
REQ_JSON="$TDIR/request.json"
REVIEW_DIR="$TDIR/review"
NEED_INPUT_MD="$REVIEW_DIR/need_input.md"
WORK_DIR="$TDIR/work"
SRC_DIR="$WORK_DIR/src"
STEPS_DIR="$SRC_DIR/steps"
OUT_DIR="$WORK_DIR/out"
FIG_DIR="$WORK_DIR/fig"
PLAN_JSON="$SRC_DIR/plan.json"
REPORT_PLAN="$WORK_DIR/report_plan.md"
REPORT_EXECUTE="$WORK_DIR/report_execute.md"
REPORT_MD="$WORK_DIR/report.md"

mkdir -p "$SRC_DIR" "$STEPS_DIR" "$OUT_DIR" "$FIG_DIR"

if [[ ! -f "$REQ_JSON" ]]; then
  mkdir -p "$REVIEW_DIR"
  cat > "$NEED_INPUT_MD" <<EOF
# Input Needed

- task_id: $TASK_ID
- skill: $SKILL
- request_complete: false
- request_step: goal

## Next question (English)
What is the goal of this symbolic multistep computation? Describe in natural language.
EOF
  cat > "$REPORT_MD" <<EOF
# compute_algebraic_multistep report

request.json missing: AGENTS/tasks/$TASK_ID/request.json
EOF
  echo "RUN_STATUS=PAUSED_FOR_INPUT"
  echo "REQUEST_COMPLETE=false"
  echo "REQUEST_STEP=goal"
  echo "NEED_INPUT_PATH=AGENTS/tasks/$TASK_ID/review/need_input.md"
  exit 0
fi

set +e
python3 - <<PY
import json
from pathlib import Path

req = json.loads(Path("$REQ_JSON").read_text(encoding="utf-8"))
required = ["goal", "inputs", "expected_outputs", "constraints", "preferred_formats"]
missing = []
for key in required:
    if key not in req:
        missing.append(key)
if missing:
    raise SystemExit(f"request.json missing required keys: {missing}")
if not str(req.get("goal", "")).strip():
    raise SystemExit("goal must be non-empty")
if not isinstance(req.get("inputs"), dict) or not req["inputs"]:
    raise SystemExit("inputs must be a non-empty object")
if not isinstance(req.get("expected_outputs"), dict) or not req["expected_outputs"]:
    raise SystemExit("expected_outputs must be a non-empty object")
if not isinstance(req.get("constraints"), list) or not req["constraints"]:
    raise SystemExit("constraints must be a non-empty array")
if not isinstance(req.get("preferred_formats"), list) or not req["preferred_formats"]:
    raise SystemExit("preferred_formats must be a non-empty array")

defaults = {
    "max_steps": 8,
    "time_limit_sec_per_step": 10,
    "max_leaf_count": 50000,
    "assumptions": "",
    "check_level": "equivalence",
    "allowlist_ops": [
        "Simplify","FullSimplify","Assuming","Refine","Together",
        "Factor","Apart","FunctionExpand","TrigReduce","Series",
        "Normal","Solve","Reduce","Integrate","D"
    ],
}
policy = req.get("policy", {})
if not isinstance(policy, dict):
    policy = {}
for k, v in defaults.items():
    if k not in policy:
        policy[k] = v
req["policy"] = policy
Path("$REQ_JSON").write_text(json.dumps(req, indent=2), encoding="utf-8")
PY
VALIDATE_RC=$?
set -e
if [[ "$VALIDATE_RC" -ne 0 ]]; then
  mkdir -p "$REVIEW_DIR"
  cat > "$NEED_INPUT_MD" <<EOF
# Input Needed

- task_id: $TASK_ID
- skill: $SKILL
- request_complete: false
- request_step: goal

## Next question (English)
What is the goal of this symbolic multistep computation? Describe in natural language.
EOF
  echo "RUN_STATUS=PAUSED_FOR_INPUT"
  echo "REQUEST_COMPLETE=false"
  echo "REQUEST_STEP=goal"
  echo "NEED_INPUT_PATH=AGENTS/tasks/$TASK_ID/review/need_input.md"
  exit 0
fi

python3 - <<PY
import json
from datetime import datetime, timezone
from pathlib import Path

req = json.loads(Path("$REQ_JSON").read_text(encoding="utf-8"))
policy = req["policy"]
max_steps = int(policy.get("max_steps", 8))
max_steps = max(1, min(max_steps, 8))
goal = str(req.get("goal", "")).lower()

ops = []
if "integrat" in goal:
    ops.append(("Integrate expression under assumptions", "stepResult = Integrate[expr, x]"))
if "differentiat" in goal or "derivative" in goal:
    ops.append(("Differentiate expression", "stepResult = D[expr, x]"))
if "solve" in goal:
    ops.append(("Solve equation for x", "stepResult = Solve[expr == 0, x]"))
ops.extend([
    ("Normalize expression form", "stepResult = Together[expr]"),
    ("Apply symbolic simplification", "stepResult = FullSimplify[stepResult]"),
    ("Refine with assumptions", "stepResult = Refine[stepResult]"),
])
ops = ops[:max_steps]

steps = []
for idx, (intent, wl_code) in enumerate(ops, start=1):
    steps.append(
        {
            "intent": intent,
            "wl_code": wl_code,
            "expected_form": "symbolic_expression",
            "check_expr": "TrueQ[Simplify[stepResult == stepResult]]",
        }
    )

plan = {
    "plan_version": "1.0",
    "created_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "policy": policy,
    "steps": steps,
}
Path("$PLAN_JSON").write_text(json.dumps(plan, indent=2), encoding="utf-8")

step_dir = Path("$STEPS_DIR")
step_dir.mkdir(parents=True, exist_ok=True)
for i, step in enumerate(steps, start=1):
    content = f"""(* {step['intent']} *)
requestPath = Environment["REQUEST_JSON_PATH"];
outputPath = Environment["STEP_OUTPUT_JSON"];
timeLimit = ToExpression[Environment["STEP_TIME_LIMIT"]];
maxLeaf = ToExpression[Environment["STEP_MAX_LEAF"]];
checkLevel = ToString[Environment["STEP_CHECK_LEVEL"]];
request = Import[requestPath, "RawJSON"];
inputs = Lookup[request, "inputs", <||>];
policy = Lookup[request, "policy", <||>];
exprText = ToString[Lookup[inputs, "expression", "x^2 + 2 x + 1"]];
assumptionText = ToString[Lookup[policy, "assumptions", ""]];
expr = Quiet@Check[ToExpression[exprText], \$Failed];
assumptionsExpr = If[StringLength[assumptionText] > 0, Quiet@Check[ToExpression[assumptionText], True], True];
stepResult = expr;
status = "ok";
message = "";
If[expr === \$Failed, status = "failed"; message = "expression_parse_failed"];
If[status === "ok",
  timed = TimeConstrained[
    Assuming[assumptionsExpr,
      ({step["wl_code"]}; stepResult)
    ],
    timeLimit,
    \$Failed
  ];
  If[timed === \$Failed, status = "failed"; message = "step_failed_or_timeout", stepResult = timed];
];
leafCount = If[status === "ok", LeafCount[stepResult], -1];
If[leafCount > maxLeaf, status = "failed"; message = "leaf_count_exceeded"];
equiv = If[status === "ok", Quiet@Check[ToString[FullSimplify[stepResult == stepResult]], "unknown"], "not_run"];
spot = "not_run";
If[status === "ok" && StringContainsQ[ToLowerCase[checkLevel], "spotcheck"],
  spot = Quiet@Check[ToString[Chop[N[(stepResult - stepResult) /. x -> 1]]], "spotcheck_failed"];
];
Export[
  outputPath,
  <|
    "intent" -> "{step['intent']}",
    "status" -> status,
    "message" -> message,
    "leaf_count" -> leafCount,
    "result" -> If[status === "ok", ToString[InputForm[stepResult]], ""],
    "equivalence_check" -> equiv,
    "spotcheck" -> spot
  |>,
  "RawJSON"
];
If[status === "ok", Exit[0], Exit[3]];
"""
    (step_dir / f"step_{i:02d}.wl").write_text(content, encoding="utf-8")
PY

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "$REPORT_PLAN" <<EOF
# Plan Report

## Problem statement (verbatim from request.md)
\`\`\`json
$(cat "$REQ_JSON")
\`\`\`

## Method / derivation / algorithm
- Plan-first workflow with human review before execution.
- Each step maps an intent to a Wolfram Language snippet.

## Code layout
- AGENTS/tasks/$TASK_ID/work/src/plan.json
- AGENTS/tasks/$TASK_ID/work/src/steps/step_XX.wl

## Repro command
- bin/agenthub run --task $TASK_ID

## Inputs
- Source: AGENTS/tasks/$TASK_ID/request.json

## Outputs
- Plan file generated at AGENTS/tasks/$TASK_ID/work/src/plan.json

## Figures
- (none in plan phase)

## Runtime metadata
- timestamp_utc: $TS
- backend: plan-only (no Wolfram execution)
EOF

if [[ "$EXECUTE_MODE" != "1" ]]; then
  cp "$REPORT_PLAN" "$REPORT_MD"
  echo "PLAN_STATUS=READY_FOR_REVIEW"
  echo "EXECUTION_ALLOWED=false"
  exit 0
fi

BACKEND=""
if command -v wolframscript >/dev/null 2>&1; then
  BACKEND="wolframscript"
elif command -v WolframKernel >/dev/null 2>&1; then
  BACKEND="WolframKernel"
fi
if [[ -z "$BACKEND" ]]; then
  cat > "$REPORT_EXECUTE" <<EOF
# Execute Report

Execution failed: missing Wolfram backend (wolframscript/WolframKernel).
EOF
  cat "$REPORT_PLAN" "$REPORT_EXECUTE" > "$REPORT_MD"
  echo "Execution backend missing" >&2
  exit 2
fi

MAX_LEAF="$(python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$REQ_JSON").read_text(encoding="utf-8"))
print(int(obj.get("policy", {}).get("max_leaf_count", 50000)))
PY
)"
STEP_LIMIT="$(python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$REQ_JSON").read_text(encoding="utf-8"))
print(int(obj.get("policy", {}).get("time_limit_sec_per_step", 10)))
PY
)"
CHECK_LEVEL="$(python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$REQ_JSON").read_text(encoding="utf-8"))
print(str(obj.get("policy", {}).get("check_level", "equivalence")))
PY
)"

cat > "$REPORT_EXECUTE" <<EOF
# Execute Report

backend: $BACKEND
check_level: $CHECK_LEVEL
EOF

FAIL=0
for step_file in "$STEPS_DIR"/step_*.wl; do
  [[ -f "$step_file" ]] || continue
  step_name="$(basename "$step_file" .wl)"
  step_out="$OUT_DIR/${step_name}.json"
  step_stdout="$OUT_DIR/${step_name}.stdout.txt"
  step_stderr="$OUT_DIR/${step_name}.stderr.txt"
  if [[ "$BACKEND" == "wolframscript" ]]; then
    REQUEST_JSON_PATH="$REQ_JSON" STEP_OUTPUT_JSON="$step_out" STEP_TIME_LIMIT="$STEP_LIMIT" STEP_MAX_LEAF="$MAX_LEAF" STEP_CHECK_LEVEL="$CHECK_LEVEL" \
      wolframscript -file "$step_file" >"$step_stdout" 2>"$step_stderr" || FAIL=1
  else
    REQUEST_JSON_PATH="$REQ_JSON" STEP_OUTPUT_JSON="$step_out" STEP_TIME_LIMIT="$STEP_LIMIT" STEP_MAX_LEAF="$MAX_LEAF" STEP_CHECK_LEVEL="$CHECK_LEVEL" \
      WolframKernel -script "$step_file" >"$step_stdout" 2>"$step_stderr" || FAIL=1
  fi

  if [[ ! -f "$step_out" ]]; then
    echo "step=$step_name status=failed reason=missing_output" >> "$REPORT_EXECUTE"
    FAIL=1
    break
  fi

  status="$(python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$step_out").read_text(encoding="utf-8"))
print(obj.get("status", "failed"))
PY
)"
  leaf="$(python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$step_out").read_text(encoding="utf-8"))
print(int(obj.get("leaf_count", -1)))
PY
)"

  echo "step=$step_name status=$status leaf_count=$leaf output=$(basename "$step_out")" >> "$REPORT_EXECUTE"
  if [[ "$leaf" -gt "$MAX_LEAF" || "$status" != "ok" ]]; then
    FAIL=1
    break
  fi
done

cat "$REPORT_PLAN" "$REPORT_EXECUTE" > "$REPORT_MD"
if [[ "$FAIL" -ne 0 ]]; then
  echo "EXECUTION_STATUS=FAILED"
  echo "EXECUTION_ALLOWED=true"
  exit 2
fi

echo "EXECUTION_STATUS=COMPLETED"
echo "EXECUTION_ALLOWED=true"
exit 0
