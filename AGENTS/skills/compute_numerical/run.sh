#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="compute_numerical"
BACKEND="python"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
WORK_COMPUTE="$TDIR/work/compute"
SCRATCH="$WORK_COMPUTE/scratch"
RUN_DIR="$WORK_COMPUTE/run"
OUTPUTS="$TDIR/outputs/compute"
LOGS="$TDIR/logs/compute"
REVIEW_DIR="$TDIR/review"
DELIV_SRC="$TDIR/deliverable/src"
DELIV_PROMO="$TDIR/deliverable/promotion_instructions.md"
RESULT_JSON="$OUTPUTS/result.json"
HASHES_JSON="$LOGS/hashes.json"
CONSENT_JSON="$LOGS/consent.json"
RESOLVED_JSON="$LOGS/resolved_request.json"
ENV_JSON="$LOGS/env.json"
REPORT="$REVIEW_DIR/compute_numerical_report.md"
SPEC_FILE="$WORK_COMPUTE/spec.yaml"
CMD_LOG="$LOGS/commands.txt"
STDOUT_LOG="$LOGS/stdout.log"
STDERR_LOG="$LOGS/stderr.log"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi

mkdir -p "$SCRATCH" "$RUN_DIR" "$OUTPUTS" "$LOGS" "$REVIEW_DIR" "$TDIR/deliverable"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

log_cmd() { printf '%s\n' "$*" >> "$CMD_LOG"; }
sha() {
  if [[ -f "$1" ]]; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo ""
  fi
}

cat > "$SPEC_FILE" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "backend": "$BACKEND",
  "params": {
    "alpha": 1.25,
    "beta": 0.75,
    "grid": [0, 1, 2, 3, 4, 5],
    "rtol": 1e-8,
    "atol": 1e-10,
    "keep_intermediates": false
  }
}
EOF2
cp "$SPEC_FILE" "$RESOLVED_JSON"

cat > "$SCRATCH/main.py" <<'EOF2'
#!/usr/bin/env python3
"""Numerical demo compute: linear transform over a small grid.

Writes structured result JSON with sanity checks and diagnostics.
"""
import json
import math
import os
from pathlib import Path

spec = json.loads(Path(os.environ["SPEC_PATH"]).read_text(encoding="utf-8"))
params = spec["params"]
alpha = float(params["alpha"])
beta = float(params["beta"])
grid = [float(x) for x in params["grid"]]

values = [alpha * x + beta for x in grid]
finite = all(math.isfinite(v) for v in values)
monotone = all(values[i] <= values[i + 1] for i in range(len(values) - 1))
mean_v = (sum(values) / len(values)) if values else None

payload = {
    "meta": {
        "task_id": spec["task_id"],
        "skill": spec["skill"],
        "backend": spec["backend"],
        "timestamp_utc": os.environ.get("RUN_TIMESTAMP", ""),
        "status": "ok",
    },
    "params": {
        "alpha": alpha,
        "beta": beta,
        "rtol": params.get("rtol"),
        "atol": params.get("atol"),
    },
    "results": {
        "summary": "Computed affine transform over grid.",
        "grid": grid,
        "values": values,
        "mean": mean_v,
    },
    "sanity_checks": [
        {"name": "length_match", "pass": len(grid) == len(values), "value": len(values), "note": "grid/value lengths"},
        {"name": "finite_values", "pass": finite, "value": finite, "note": "all outputs finite"},
        {"name": "monotonic_values", "pass": monotone, "value": monotone, "note": "expected with positive alpha"},
    ],
    "diagnostics": {
        "convergence": "not_applicable",
        "stability": {
            "rtol": params.get("rtol"),
            "atol": params.get("atol"),
            "note": "deterministic closed-form evaluation",
        },
    },
}

out = Path(os.environ["RESULT_PATH"])
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(payload, indent=2), encoding="utf-8")
EOF2
chmod +x "$SCRATCH/main.py"

log_cmd "cp $SCRATCH/main.py $RUN_DIR/main.py"
cp "$SCRATCH/main.py" "$RUN_DIR/main.py"

PY_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PY_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PY_BIN="python"
fi

RUN_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "$ENV_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "backend": "$BACKEND",
  "timestamp_utc": "$RUN_TS",
  "python": "$( [[ -n "$PY_BIN" ]] && $PY_BIN --version 2>&1 | head -n 1 || echo unavailable )",
  "wolframscript": "$( command -v wolframscript >/dev/null 2>&1 && wolframscript -version 2>&1 | head -n 1 || echo unavailable )"
}
EOF2

STATUS="ok"
if [[ -z "$PY_BIN" ]]; then
  STATUS="backend_unavailable"
  cat > "$RESULT_JSON" <<EOF2
{
  "meta": {
    "task_id": "$TASK_ID",
    "skill": "$SKILL",
    "backend": "$BACKEND",
    "timestamp_utc": "$RUN_TS",
    "status": "backend_unavailable"
  },
  "params": {"note": "python backend missing"},
  "results": {"summary": "No computation executed."},
  "sanity_checks": [
    {"name": "backend_available", "pass": false, "value": false, "note": "python3/python not found"}
  ],
  "diagnostics": {"convergence": "not_run", "stability": "not_run"}
}
EOF2
  log_cmd "backend unavailable: python3/python not found"
else
  log_cmd "cd $RUN_DIR && SPEC_PATH=$SPEC_FILE RESULT_PATH=$RESULT_JSON RUN_TIMESTAMP=$RUN_TS $PY_BIN main.py"
  set +e
  (cd "$RUN_DIR" && SPEC_PATH="$SPEC_FILE" RESULT_PATH="$RESULT_JSON" RUN_TIMESTAMP="$RUN_TS" "$PY_BIN" main.py)
  RC=$?
  set -e
  if [[ "$RC" -ne 0 || ! -f "$RESULT_JSON" ]]; then
    STATUS="failed"
    cat > "$RESULT_JSON" <<EOF2
{
  "meta": {
    "task_id": "$TASK_ID",
    "skill": "$SKILL",
    "backend": "$BACKEND",
    "timestamp_utc": "$RUN_TS",
    "status": "failed"
  },
  "params": {"note": "execution failed"},
  "results": {"summary": "Computation failed; inspect logs."},
  "sanity_checks": [
    {"name": "run_exit_zero", "pass": false, "value": $RC, "note": "python run failed"}
  ],
  "diagnostics": {"convergence": "unknown", "stability": "unknown"}
}
EOF2
  fi
fi

RESP=""
EXPORTED=false
if rg -q '"status": "ok"' "$RESULT_JSON"; then
  echo "Compute succeeded. Export a cleaned, commented program into deliverable/src? (y/N)"
  if read -r RESP; then
    :
  else
    RESP=""
  fi
  RESP_LC="$(printf '%s' "$RESP" | tr '[:upper:]' '[:lower:]')"
  if [[ "$RESP_LC" == "y" ]]; then
    EXPORTED=true
    mkdir -p "$DELIV_SRC"
    cat > "$DELIV_SRC/main.py" <<'EOF2'
#!/usr/bin/env python3
"""Numerical compute example (exported clean source).

This program evaluates an affine model over a configured grid and writes result JSON.
Edit parameters in the SPEC_PATH file to play around.
"""
import json
import math
import os
from pathlib import Path

spec = json.loads(Path(os.environ["SPEC_PATH"]).read_text(encoding="utf-8"))
params = spec["params"]
alpha = float(params["alpha"])
beta = float(params["beta"])
grid = [float(x) for x in params["grid"]]

# Core numerical model.
values = [alpha * x + beta for x in grid]
finite = all(math.isfinite(v) for v in values)

payload = {
    "meta": spec,
    "params": params,
    "results": {
        "summary": "Affine numerical scan",
        "grid": grid,
        "values": values,
        "mean": (sum(values) / len(values)) if values else None,
    },
    "sanity_checks": [
        {"name": "length_match", "pass": len(grid) == len(values), "value": len(values), "note": "grid/value lengths"},
        {"name": "finite_values", "pass": finite, "value": finite, "note": "all outputs finite"},
    ],
    "diagnostics": {
        "convergence": "not_applicable",
        "stability": {"tolerance_hint": [params.get("rtol"), params.get("atol")]},
    },
}

out = Path(os.environ.get("RESULT_PATH", "result.json"))
out.write_text(json.dumps(payload, indent=2), encoding="utf-8")
EOF2
    chmod +x "$DELIV_SRC/main.py"
    cat > "$DELIV_SRC/README.md" <<EOF2
# Numerical Compute Program

This program computes a simple affine numerical scan over a grid and records sanity checks plus stability notes.

## Run
\`SPEC_PATH=AGENTS/tasks/$TASK_ID/work/compute/spec.yaml RESULT_PATH=AGENTS/tasks/$TASK_ID/outputs/compute/result.json python3 AGENTS/tasks/$TASK_ID/deliverable/src/main.py\`

## Inputs
- \`AGENTS/tasks/$TASK_ID/work/compute/spec.yaml\`

## Outputs
- \`AGENTS/tasks/$TASK_ID/outputs/compute/result.json\`
- optional \`tables/*.csv\` and \`fig/*\` if added later

## Tolerances / stability checks
- Adjust \`params.rtol\` and \`params.atol\` in \`spec.yaml\`.

## Play around
- Edit \`params.alpha\`, \`params.beta\`, and \`params.grid\` in \`spec.yaml\`.
EOF2
  else
    rm -rf "$DELIV_SRC"
  fi
else
  RESP=""
fi

cat > "$CONSENT_JSON" <<EOF2
{
  "exported_source": $EXPORTED,
  "user_response": "$(printf '%s' "$RESP" | tr '[:upper:]' '[:lower:]')",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF2

cat > "$DELIV_PROMO" <<EOF2
# Promotion Instructions

Agents cannot write to USER directly.

If exported source exists, manually promote with:

\`cp -r AGENTS/tasks/$TASK_ID/deliverable/src USER/src/compute/$TASK_ID/\`

Recommended destination:
- \`USER/src/compute/$TASK_ID/\`

If export was declined, rerun and answer \`y\` to generate \`deliverable/src\`.
EOF2

{
  echo "{"
  echo "  \"generated_at_utc\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
  echo "  \"inputs\": ["
  echo "    {\"path\": \"$SPEC_FILE\", \"sha256\": \"$(sha "$SPEC_FILE")\"}"
  echo "  ],"
  echo "  \"outputs\": ["
  echo "    {\"path\": \"$RESULT_JSON\", \"sha256\": \"$(sha "$RESULT_JSON")\"},"
  echo "    {\"path\": \"$CONSENT_JSON\", \"sha256\": \"$(sha "$CONSENT_JSON")\"}"
  echo "  ]"
  echo "}"
} > "$HASHES_JSON"

RESULT_STATUS="$(sed -n 's/^[[:space:]]*"status":[[:space:]]*"\([^"]*\)".*/\1/p' "$RESULT_JSON" | head -n 1)"
if [[ "$RESULT_STATUS" == "ok" ]]; then
  # Cleanup byproducts on successful runs; keep outputs/logs.
  rm -rf "$RUN_DIR/__pycache__" "$RUN_DIR/.ipynb_checkpoints"
  find "$RUN_DIR" -type f \( -name '*.tmp' -o -name '*.bak' \) -delete || true
  find "$SCRATCH" -mindepth 1 -delete || true
  CLEANUP_NOTE="transient byproducts cleaned"
else
  CLEANUP_NOTE="run failed or backend unavailable; preserved scratch/run for forensics"
fi

{
  echo "# compute_numerical Report"
  echo
  echo "- task_id: $TASK_ID"
  echo "- backend: $BACKEND"
  echo "- status: $RESULT_STATUS"
  echo "- exported_source: $EXPORTED"
  echo "- cleanup: $CLEANUP_NOTE"
  echo
  echo "## Paths"
  echo "- spec: AGENTS/tasks/$TASK_ID/work/compute/spec.yaml"
  echo "- result: AGENTS/tasks/$TASK_ID/outputs/compute/result.json"
  echo "- logs: AGENTS/tasks/$TASK_ID/logs/compute/"
} > "$REPORT"

bash "$ROOT/AGENTS/runtime/stage_to_gate.sh" "$ROOT" "$TASK_ID" "$SKILL"

exit 0
