#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="compute_numerical"

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
MAIN_PY="$SRC_DIR/main.py"
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
# Compute Numerical Report

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
- python_version: $(python3 --version 2>&1 | tr -d '\r')
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
# Compute Numerical Report

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
- python_version: $(python3 --version 2>&1 | tr -d '\r')
EOF
  echo "REQUEST_COMPLETE=false"
  echo "REQUEST_STEP=goal"
  echo "RUN_STATUS=PAUSED_FOR_INPUT"
  echo "NEED_INPUT_PATH=AGENTS/tasks/$TASK_ID/review/need_input.md"
  exit 0
fi

cat > "$MAIN_PY" <<'PY'
#!/usr/bin/env python3
"""Generated numerical compute program.

Implements:
- parse_inputs()
- compute()
- emit_outputs()
"""

import argparse
import json
from pathlib import Path


def parse_inputs(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def compute(payload: dict) -> dict:
    inputs = payload.get("inputs", {})
    x_values = inputs.get("x_values", [-3, -2, -1, 0, 1, 2, 3])
    coeffs = inputs.get("coefficients", {})
    a = float(coeffs.get("a", 1.0))
    b = float(coeffs.get("b", 0.0))
    c = float(coeffs.get("c", 0.0))
    y_values = [a * (float(x) ** 2.0) + b * float(x) + c for x in x_values]
    return {
        "mode": str(inputs.get("mode", "quadratic_scan")),
        "parameters": {"a": a, "b": b, "c": c},
        "series": [{"x": float(x), "y": float(y)} for x, y in zip(x_values, y_values)],
        "summary": {
            "count": len(y_values),
            "min_y": min(y_values) if y_values else None,
            "max_y": max(y_values) if y_values else None,
            "mean_y": (sum(y_values) / len(y_values)) if y_values else None,
        },
        "plot_requested": bool(inputs.get("make_plot", False)),
    }


def emit_outputs(payload: dict, result: dict, result_path: str, fig_dir: str) -> list:
    out = {
        "goal": payload.get("goal", ""),
        "inputs": payload.get("inputs", {}),
        "expected_outputs": payload.get("expected_outputs", {}),
        "result": result,
    }
    result_file = Path(result_path)
    result_file.parent.mkdir(parents=True, exist_ok=True)
    result_file.write_text(json.dumps(out, indent=2, sort_keys=True), encoding="utf-8")

    figs = []
    if result.get("plot_requested", False):
        try:
            import matplotlib.pyplot as plt  # type: ignore
        except Exception as exc:
            out["plot_warning"] = f"plot skipped: matplotlib unavailable ({exc})"
            result_file.write_text(json.dumps(out, indent=2, sort_keys=True), encoding="utf-8")
            return figs
        fig_path = Path(fig_dir) / "quadratic_scan.png"
        fig_path.parent.mkdir(parents=True, exist_ok=True)
        xs = [item["x"] for item in result["series"]]
        ys = [item["y"] for item in result["series"]]
        plt.figure(figsize=(6, 4))
        plt.plot(xs, ys, marker="o")
        plt.title("Quadratic Scan")
        plt.xlabel("x")
        plt.ylabel("y")
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(fig_path)
        plt.close()
        figs.append(str(fig_path))
    return figs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inputs", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--fig-dir", required=True)
    args = parser.parse_args()

    payload = parse_inputs(args.inputs)
    result = compute(payload)
    figs = emit_outputs(payload, result, args.result, args.fig_dir)

    print(f"mode={result.get('mode')}")
    print(f"count={result.get('summary', {}).get('count')}")
    print(f"result_json={args.result}")
    if figs:
        print(f"figures={','.join(figs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "$MAIN_PY"

REPRO_CMD="python3 AGENTS/tasks/$TASK_ID/work/src/main.py --inputs AGENTS/tasks/$TASK_ID/work/out/artifacts/inputs.json --result AGENTS/tasks/$TASK_ID/work/out/artifacts/result.json --fig-dir AGENTS/tasks/$TASK_ID/work/fig"
mkdir -p "$ART_DIR/mplconfig"
set +e
MPLBACKEND=Agg MPLCONFIGDIR="$ART_DIR/mplconfig" \
  python3 "$MAIN_PY" --inputs "$INPUTS_JSON" --result "$RESULT_JSON" --fig-dir "$FIG_DIR" >"$STDOUT_PATH" 2>"$STDERR_PATH"
RUN_RC=$?
set -e

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
PY_VER="$(python3 --version 2>&1 | tr -d '\r')"
MPL_VER="$(python3 - <<'PY'
try:
    import matplotlib  # type: ignore
    print(matplotlib.__version__)
except Exception:
    print("not-installed")
PY
)"
FIG_LIST="$(find "$FIG_DIR" -maxdepth 1 -type f | sort | sed "s#^$ROOT/##")"
[[ -n "$FIG_LIST" ]] || FIG_LIST="(none)"

RESULT_PREVIEW="(missing)"
if [[ -f "$RESULT_JSON" ]]; then
  RESULT_PREVIEW="$(python3 - <<PY
import json
from pathlib import Path
obj = json.loads(Path("$RESULT_JSON").read_text(encoding="utf-8"))
print(json.dumps(obj.get("result", {}).get("summary", {}), indent=2, sort_keys=True))
PY
)"
fi

cat > "$REPORT_PATH" <<EOF
# Compute Numerical Report

## Problem statement (verbatim from request.md)
--- BEGIN REQUEST ---
$(cat "$REQ_TXT")
--- END REQUEST ---

## Method / derivation / algorithm
- Parse structured JSON inputs from request.md.
- Evaluate a deterministic quadratic scan y = a*x^2 + b*x + c over provided x_values.
- Emit structured JSON outputs and optional matplotlib figure.

## Code layout
- AGENTS/tasks/$TASK_ID/work/src/main.py
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
- Run exit code: $RUN_RC
- Result file: AGENTS/tasks/$TASK_ID/work/out/artifacts/result.json
--- BEGIN RESULT SUMMARY ---
$RESULT_PREVIEW
--- END RESULT SUMMARY ---

## Figures
$FIG_LIST

## Runtime metadata
- timestamp_utc: $TS
- python_version: $PY_VER
- matplotlib_version: $MPL_VER
EOF

if [[ "$RUN_RC" -ne 0 ]]; then
  echo "Numerical compute failed. See $STDERR_PATH" >&2
  exit 2
fi

bash "$ROOT/AGENTS/runtime/stage_to_gate.sh" "$ROOT" "$TASK_ID" "$SKILL"
echo "$SKILL completed for task $TASK_ID"
