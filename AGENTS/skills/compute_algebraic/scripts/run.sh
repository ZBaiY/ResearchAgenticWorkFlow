#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="compute_algebraic"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
REQ_PATH="$TDIR/request.md"
REQ_JSON="$TDIR/request.json"
REVIEW_DIR="$TDIR/review"
NEED_INPUT_MD="$REVIEW_DIR/need_input.md"
WORK_DIR="$TDIR/work"
SRC_DIR="$WORK_DIR/src"
OUT_DIR="$WORK_DIR/out"
ART_DIR="$OUT_DIR/artifacts"
FIG_DIR="$WORK_DIR/fig"
REPORT_PATH="$WORK_DIR/report.md"
STDOUT_PATH="$OUT_DIR/stdout.txt"
STDERR_PATH="$OUT_DIR/stderr.txt"
INPUTS_JSON="$ART_DIR/inputs.json"
RESULT_JSON="$ART_DIR/result.json"
MAIN_WL="$SRC_DIR/main.wl"
REQ_TXT="$ART_DIR/request_verbatim.txt"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi
if [[ ! -f "$REQ_JSON" ]]; then
  mkdir -p "$REVIEW_DIR"
  cat > "$NEED_INPUT_MD" <<EOF
# Input Needed

- task_id: $TASK_ID
- skill: $SKILL
- request_complete: false
- request_step: goal

## Next question (English)
What is the goal of this computation? (Describe in natural language; you can be detailed.)
EOF
  mkdir -p "$WORK_DIR"
  cat > "$REPORT_PATH" <<EOF
# Compute Algebraic Report

## Problem statement (verbatim from request.md)
request.json is missing.

## Method / derivation / algorithm
Run aborted because request schema is incomplete.

## Code layout
(not generated)

## Repro command
(not executed)

## Inputs
(missing request.json)

## Outputs
- status: paused
- reason: request.json missing

## Figures
(none)

## Runtime metadata
- timestamp_utc: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- backend: none
- backend_version: unavailable
EOF
  echo "REQUEST_COMPLETE=false"
  echo "REQUEST_STEP=goal"
  echo "RUN_STATUS=PAUSED_FOR_INPUT"
  echo "NEED_INPUT_PATH=AGENTS/tasks/$TASK_ID/review/need_input.md"
  exit 0
fi

mkdir -p "$SRC_DIR" "$OUT_DIR" "$ART_DIR" "$FIG_DIR"

set +e
REQ_PATH_ENV="$REQ_PATH" REQ_JSON_ENV="$REQ_JSON" INPUTS_JSON_ENV="$INPUTS_JSON" REQ_TXT_ENV="$REQ_TXT" python3 - <<'PY'
import json
import os
from pathlib import Path

req_path = Path(os.environ["REQ_PATH_ENV"])
req_json = Path(os.environ["REQ_JSON_ENV"])
text = req_path.read_text(encoding="utf-8") if req_path.exists() else "(request.md not present)"
payload = json.loads(req_json.read_text(encoding="utf-8"))
required = ["goal", "inputs", "expected_outputs", "constraints", "preferred_formats"]
missing = []
for key in required:
    if key not in payload:
        missing.append(key)
if missing:
    raise SystemExit(f"request.json missing required keys: {missing}")
if not str(payload.get("goal", "")).strip():
    raise SystemExit("request.json goal must be non-empty")
if not isinstance(payload.get("inputs"), dict) or len(payload.get("inputs", {})) == 0:
    raise SystemExit("request.json inputs must be a non-empty object")
if not isinstance(payload.get("expected_outputs"), dict) or len(payload.get("expected_outputs", {})) == 0:
    raise SystemExit("request.json expected_outputs must be a non-empty object")
if not isinstance(payload.get("constraints"), list) or len(payload.get("constraints", [])) == 0:
    raise SystemExit("request.json constraints must be a non-empty array")
if not isinstance(payload.get("preferred_formats"), list) or len(payload.get("preferred_formats", [])) == 0:
    raise SystemExit("request.json preferred_formats must be a non-empty array")
Path(os.environ["INPUTS_JSON_ENV"]).write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
Path(os.environ["REQ_TXT_ENV"]).write_text(text, encoding="utf-8")
PY
VALIDATE_RC=$?
set -e

if [[ "$VALIDATE_RC" -ne 0 || ! -f "$INPUTS_JSON" ]]; then
  mkdir -p "$REVIEW_DIR"
  cat > "$NEED_INPUT_MD" <<EOF
# Input Needed

- task_id: $TASK_ID
- skill: $SKILL
- request_complete: false
- request_step: goal

## Next question (English)
What is the goal of this computation? (Describe in natural language; you can be detailed.)
EOF
  cat > "$REPORT_PATH" <<EOF
# Compute Algebraic Report

## Problem statement (verbatim from request.md)
$(cat "$REQ_TXT" 2>/dev/null || true)

## Method / derivation / algorithm
Run aborted because request schema is incomplete.

## Code layout
(not generated)

## Repro command
(not executed)

## Inputs
(invalid request.json)

## Outputs
- status: paused
- reason: request.json missing required fields or non-empty values

## Figures
(none)

## Runtime metadata
- timestamp_utc: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- backend: none
- backend_version: unavailable
EOF
  echo "REQUEST_COMPLETE=false"
  echo "REQUEST_STEP=goal"
  echo "RUN_STATUS=PAUSED_FOR_INPUT"
  echo "NEED_INPUT_PATH=AGENTS/tasks/$TASK_ID/review/need_input.md"
  exit 0
fi

cat > "$MAIN_WL" <<'WL'
(* Generated symbolic/algebraic compute script.
   Reads INPUT_JSON, writes RESULT_JSON, optional figure into FIG_DIR. *)

inputPath = Environment["INPUT_JSON"];
resultPath = Environment["RESULT_JSON"];
figDir = Environment["FIG_DIR"];

If[StringLength[inputPath] == 0 || StringLength[resultPath] == 0 || StringLength[figDir] == 0,
  Print["missing required environment variables INPUT_JSON/RESULT_JSON/FIG_DIR"];
  Exit[2];
];

CreateDirectory[figDir, CreateIntermediateDirectories -> True];

data = Import[inputPath, "RawJSON"];
goal = ToString[Lookup[data, "goal", ""]];
inputs = Lookup[data, "inputs", <||>];
operation = ToLowerCase[ToString[Lookup[inputs, "operation", "simplify"]]];
expressionText = ToString[Lookup[inputs, "expression", "(x^2-1)/(x-1)"]];
assumptionsText = ToString[Lookup[inputs, "assumptions", "True"]];
solveVariableText = ToString[Lookup[inputs, "solve_variable", "x"]];
plotExpression = TrueQ[Lookup[inputs, "plot_expression", False]];
plotRange = Lookup[inputs, "plot_range", {-5, 5}];

heldExpr = ToExpression[expressionText, InputForm, HoldComplete];
expr = ReleaseHold[heldExpr];
assumptions = Quiet@Check[ToExpression[assumptionsText, InputForm], True];
solveVariable = Quiet@Check[ToExpression[solveVariableText, InputForm], x];

resultExpr = Switch[
  operation,
  "expand", Expand[expr],
  "factor", Factor[expr],
  "simplify", FullSimplify[expr, Assumptions -> assumptions],
  "solve", Solve[expr == 0, solveVariable],
  _, FullSimplify[expr, Assumptions -> assumptions]
];

figurePath = "";
If[plotExpression,
  Quiet@Check[
    figurePath = FileNameJoin[{figDir, "algebraic_plot.png"}];
    Export[figurePath, Plot[Evaluate[expr], {solveVariable, plotRange[[1]], plotRange[[2]]}]];
  , figurePath = ""];
];

payload = <|
  "goal" -> goal,
  "operation" -> operation,
  "expression" -> expressionText,
  "assumptions" -> assumptionsText,
  "result" -> ToString[resultExpr, InputForm],
  "figure" -> figurePath
|>;

Export[resultPath, payload, "RawJSON"];
Print["operation=" <> operation];
Print["result_path=" <> resultPath];
If[StringLength[figurePath] > 0, Print["figure=" <> figurePath]];
WL

BACKEND_LABEL=""
BACKEND_VERSION="unavailable"
if command -v wolframscript >/dev/null 2>&1; then
  BACKEND_LABEL="wolframscript"
  BACKEND_VERSION="$(wolframscript -version 2>&1 | head -n 1 | tr -d '\r')"
  RUN_CMD=(wolframscript -file "$MAIN_WL")
elif command -v WolframKernel >/dev/null 2>&1; then
  BACKEND_LABEL="WolframKernel"
  BACKEND_VERSION="$(WolframKernel -version 2>&1 | head -n 1 | tr -d '\r' || true)"
  RUN_CMD=(WolframKernel -noprompt -script "$MAIN_WL")
else
  echo "No Wolfram backend found (expected wolframscript or WolframKernel)." >"$STDERR_PATH"
  : > "$STDOUT_PATH"
  RUN_RC=2
fi

if [[ -n "${BACKEND_LABEL:-}" ]]; then
  set +e
  INPUT_JSON="$INPUTS_JSON" RESULT_JSON="$RESULT_JSON" FIG_DIR="$FIG_DIR" "${RUN_CMD[@]}" >"$STDOUT_PATH" 2>"$STDERR_PATH"
  RUN_RC=$?
  set -e
fi

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
FIG_LIST="$(find "$FIG_DIR" -maxdepth 1 -type f | sort | sed "s#^$ROOT/##")"
[[ -n "$FIG_LIST" ]] || FIG_LIST="(none)"

RESULT_PREVIEW="(missing)"
if [[ -f "$RESULT_JSON" ]]; then
  RESULT_PREVIEW="$(cat "$RESULT_JSON")"
fi

REPRO_CMD="$BACKEND_LABEL with INPUT_JSON/RESULT_JSON/FIG_DIR environment against AGENTS/tasks/$TASK_ID/work/src/main.wl"

cat > "$REPORT_PATH" <<EOF
# Compute Algebraic Report

## Problem statement (verbatim from request.md)
--- BEGIN REQUEST ---
$(cat "$REQ_TXT")
--- END REQUEST ---

## Method / derivation / algorithm
- Parse structured JSON inputs from request.md.
- Convert expression/assumption strings into Wolfram expressions.
- Apply operation (expand/factor/simplify/solve) deterministically.
- Export result JSON and optional figure.

## Code layout
- AGENTS/tasks/$TASK_ID/work/src/main.wl
- AGENTS/tasks/$TASK_ID/work/out/artifacts/inputs.json
- AGENTS/tasks/$TASK_ID/work/out/artifacts/result.json
- AGENTS/tasks/$TASK_ID/work/out/stdout.txt
- AGENTS/tasks/$TASK_ID/work/out/stderr.txt
- AGENTS/tasks/$TASK_ID/work/fig/

## Repro command
--- BEGIN COMMAND ---
$REPRO_CMD
--- END COMMAND ---

## Inputs
--- BEGIN INPUTS ---
$(cat "$INPUTS_JSON")
--- END INPUTS ---

## Outputs
- Run exit code: ${RUN_RC:-2}
- Result file: AGENTS/tasks/$TASK_ID/work/out/artifacts/result.json
--- BEGIN RESULT ---
$RESULT_PREVIEW
--- END RESULT ---

## Figures
$FIG_LIST

## Runtime metadata
- timestamp_utc: $TS
- backend: ${BACKEND_LABEL:-none}
- backend_version: $BACKEND_VERSION
EOF

if [[ "${RUN_RC:-2}" -ne 0 ]]; then
  echo "Algebraic compute failed. See $STDERR_PATH" >&2
  exit 2
fi

bash "$ROOT/AGENTS/runtime/stage_to_gate.sh" "$ROOT" "$TASK_ID" "$SKILL"
echo "$SKILL completed for task $TASK_ID"
