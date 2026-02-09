#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="compute"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
WORK_COMPUTE="$TDIR/work/compute"
DELIV_COMPUTE="$TDIR/deliverable/compute"
REVIEW_DIR="$TDIR/review"
LOG_DIR="$TDIR/logs"
REPORT="$REVIEW_DIR/compute_skill_report.md"
MANIFEST="$DELIV_COMPUTE/files_manifest.json"
CMD_LOG="$LOG_DIR/commands.txt"
STDOUT_LOG="$LOG_DIR/compute.stdout.log"
STDERR_LOG="$LOG_DIR/compute.stderr.log"
GIT_STATUS_LOG="$LOG_DIR/git_status.txt"
BACKEND_FILE="$TDIR/work/compute_backend.txt"
SPEC_FILE="$WORK_COMPUTE/spec.yaml"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi

mkdir -p "$WORK_COMPUTE" "$DELIV_COMPUTE" "$REVIEW_DIR" "$LOG_DIR"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

run_cmd() {
  printf '%s\n' "$*" >> "$CMD_LOG"
  "$@"
}

BACKEND="${COMPUTE_BACKEND:-python}"
if [[ -f "$BACKEND_FILE" ]]; then
  BACKEND="$(tr '[:upper:]' '[:lower:]' < "$BACKEND_FILE" | tr -d '[:space:]')"
fi
if [[ "$BACKEND" != "python" && "$BACKEND" != "wolfram" ]]; then
  BACKEND="python"
fi

cat > "$SPEC_FILE" <<EOF2
{
  "task_id": "$TASK_ID",
  "job_name": "compute_$TASK_ID",
  "backend": "$BACKEND",
  "entry": "$( [[ "$BACKEND" == "python" ]] && echo "main.py" || echo "main.wl" )",
  "inputs": [
    {
      "name": "task_request",
      "path": "AGENTS/tasks/$TASK_ID/request.md",
      "required": false
    }
  ],
  "params": {
    "a": 2.0,
    "b": 1.0,
    "sample_points": [0, 1, 2, 3, 4],
    "uncertainty_sigma": 0.05
  },
  "sanity_checks": [
    "result_vector_length_matches_input",
    "result_values_are_finite",
    "mean_value_within_expected_range"
  ],
  "output": {
    "result_json": "AGENTS/tasks/$TASK_ID/outputs/compute/result.json",
    "hashes_json": "AGENTS/tasks/$TASK_ID/outputs/compute/hashes.json"
  }
}
EOF2

if [[ "$BACKEND" == "python" ]]; then
  rm -f "$WORK_COMPUTE/main.wl"
  cat > "$WORK_COMPUTE/main.py" <<'EOF2'
#!/usr/bin/env python3
import json
import math
import os
from pathlib import Path

spec = json.loads(os.environ.get("COMPUTE_SPEC_JSON", "{}"))
params = spec.get("params", {})
a = float(params.get("a", 2.0))
b = float(params.get("b", 1.0))
xs = params.get("sample_points", [0, 1, 2, 3, 4])

ys = [a * float(x) + b for x in xs]
finite = all(math.isfinite(v) for v in ys)

payload = {
    "backend": "python",
    "computation": "linear_model",
    "inputs": {"x": xs},
    "params": {"a": a, "b": b},
    "results": {"y": ys, "mean_y": (sum(ys) / len(ys)) if ys else None},
    "sanity_checks": [
        {"name": "result_vector_length_matches_input", "passed": len(xs) == len(ys)},
        {"name": "result_values_are_finite", "passed": finite},
        {"name": "mean_value_within_expected_range", "passed": (sum(ys) / len(ys)) < 1000 if ys else False}
    ]
}

out = os.environ.get("COMPUTE_BACKEND_OUTPUT")
if not out:
    raise SystemExit("COMPUTE_BACKEND_OUTPUT is required")
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(payload, indent=2), encoding="utf-8")
EOF2
  chmod +x "$WORK_COMPUTE/main.py"
else
  rm -f "$WORK_COMPUTE/main.py"
  cat > "$WORK_COMPUTE/main.wl" <<'EOF2'
(* Wolfram backend job payload generator *)
spec = ImportString[Environment["COMPUTE_SPEC_JSON"], "RawJSON"];
params = Lookup[spec, "params", <||>];
a = N@Lookup[params, "a", 2.0];
b = N@Lookup[params, "b", 1.0];
xs = N /@ Lookup[params, "sample_points", {0, 1, 2, 3, 4}];
ys = (a # + b) & /@ xs;
meanY = If[Length[ys] > 0, Mean[ys], Missing["NotAvailable"]];

payload = <|
  "backend" -> "wolfram",
  "computation" -> "linear_model",
  "inputs" -> <|"x" -> xs|>,
  "params" -> <|"a" -> a, "b" -> b|>,
  "results" -> <|"y" -> ys, "mean_y" -> meanY|>,
  "sanity_checks" -> {
    <|"name" -> "result_vector_length_matches_input", "passed" -> (Length[xs] == Length[ys])|>,
    <|"name" -> "result_values_are_finite", "passed" -> AllTrue[ys, NumericQ]|>,
    <|"name" -> "mean_value_within_expected_range", "passed" -> If[Length[ys] > 0, meanY < 1000, False]|>
  }
|>;

out = Environment["COMPUTE_BACKEND_OUTPUT"];
If[StringLength[out] == 0, Print["COMPUTE_BACKEND_OUTPUT is required"]; Exit[2]];
Export[out, payload, "RawJSON"];
EOF2
fi

cat > "$WORK_COMPUTE/sanity_checks.md" <<EOF2
# Compute Sanity Checks

- Verify output vector length equals input vector length.
- Verify computed values are finite.
- Verify mean value remains within expected range for configured parameters.

Command:
\`bash AGENTS/runtime/compute_runner.sh --task $TASK_ID\`
EOF2

cat > "$WORK_COMPUTE/compute_report_template.md" <<EOF2
# Compute Report Template

## What is computed
- Model/function:
- Inputs used:
- Parameter set:
- Expected output artifacts:

## Reproducibility
- Runner command:
- Environment versions:
- Input/output hashes file:

## Validation plan
- Sanity check 1:
- Sanity check 2:
- Sanity check 3:

## Interpretation notes
- Key observations:
- Known limitations:
- Follow-up experiments:
EOF2

FILES_WRITTEN=(
  "AGENTS/tasks/$TASK_ID/work/compute/spec.yaml"
  "AGENTS/tasks/$TASK_ID/work/compute/sanity_checks.md"
  "AGENTS/tasks/$TASK_ID/work/compute/compute_report_template.md"
  "AGENTS/tasks/$TASK_ID/review/compute_skill_report.md"
  "AGENTS/tasks/$TASK_ID/deliverable/compute/files_manifest.json"
  "AGENTS/tasks/$TASK_ID/logs/commands.txt"
  "AGENTS/tasks/$TASK_ID/logs/compute.stdout.log"
  "AGENTS/tasks/$TASK_ID/logs/compute.stderr.log"
  "AGENTS/tasks/$TASK_ID/logs/git_status.txt"
)
if [[ "$BACKEND" == "python" ]]; then
  FILES_WRITTEN+=("AGENTS/tasks/$TASK_ID/work/compute/main.py")
else
  FILES_WRITTEN+=("AGENTS/tasks/$TASK_ID/work/compute/main.wl")
fi

{
  echo "# compute Skill Report"
  echo
  echo "- task_id: $TASK_ID"
  echo "- backend: $BACKEND"
  echo
  echo "## Generated"
  for f in "${FILES_WRITTEN[@]}"; do
    echo "- $f"
  done
  echo
  echo "## Next step"
  echo "- Execute: bash AGENTS/runtime/compute_runner.sh --task $TASK_ID"
} > "$REPORT"

{
  echo "{"
  echo "  \"task_id\": \"$TASK_ID\"," 
  echo "  \"skill\": \"$SKILL\"," 
  echo "  \"backend\": \"$BACKEND\"," 
  echo "  \"work_compute_dir\": \"AGENTS/tasks/$TASK_ID/work/compute\"," 
  echo "  \"files_written\": ["
  for i in "${!FILES_WRITTEN[@]}"; do
    sep=","; [[ "$i" -eq $((${#FILES_WRITTEN[@]}-1)) ]] && sep=""
    echo "    \"${FILES_WRITTEN[$i]}\"$sep"
  done
  echo "  ],"
  echo "  \"status\": \"ok\"," 
  echo "  \"notes\": \"Generated deterministic compute scaffold with reproducibility hooks.\""
  echo "}"
} > "$MANIFEST"

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  run_cmd git -C "$ROOT" status --porcelain
  git -C "$ROOT" status --porcelain > "$GIT_STATUS_LOG"
else
  echo "git not available or repo missing" > "$GIT_STATUS_LOG"
fi

echo "$SKILL completed for task $TASK_ID"
exit 0
