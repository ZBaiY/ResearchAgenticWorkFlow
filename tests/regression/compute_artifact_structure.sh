#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

REQ="AGENTS/requests/regression/compute_artifact_structure.md"
mkdir -p "$(dirname "$REQ")"
cat > "$REQ" <<'EOF'
# Request

Goal:
Artifact structure regression for compute_numerical.

Inputs (JSON):
```json
{
  "goal": "Artifact structure regression for compute_numerical.",
  "inputs": {
    "mode": "quadratic_scan",
    "x_values": [-2, -1, 0, 1, 2],
    "coefficients": {"a": 1.0, "b": 0.0, "c": -1.0},
    "make_plot": false
  },
  "expected_outputs": {
    "result_file": "result.json"
  },
  "constraints": [
    "No network"
  ],
  "preferred_formats": [
    "json",
    "png"
  ]
}
```
EOF

TASK="test_compute_structure_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill compute_numerical --task-name "$TASK" --request "$REQ" >/tmp/test_compute_structure_start.out
./bin/agenthub request-set --task "$TASK" --field goal --value "Artifact structure regression for compute_numerical." >/tmp/test_compute_structure_goal.out
./bin/agenthub request-set --task "$TASK" --field inputs --value '{"mode":"quadratic_scan","x_values":[-2,-1,0,1,2],"coefficients":{"a":1.0,"b":0.0,"c":-1.0},"make_plot":false}' >/tmp/test_compute_structure_inputs.out
./bin/agenthub request-set --task "$TASK" --field expected_outputs --value '{"result_file":"result.json"}' >/tmp/test_compute_structure_expected.out
./bin/agenthub request-set --task "$TASK" --field constraints --value '["No network"]' >/tmp/test_compute_structure_constraints.out
./bin/agenthub request-set --task "$TASK" --field preferred_formats --value '["json","png"]' >/tmp/test_compute_structure_formats.out
./bin/agenthub run --task "$TASK" --yes </dev/null >/tmp/test_compute_structure_run.out

TDIR="AGENTS/tasks/$TASK"
SDIR="GATE/staged/$TASK/compute_numerical"
PROMOTE_JSON="GATE/staged/$TASK/PROMOTE.json"

[[ -f "$TDIR/work/src/main.py" ]] || { echo "FAIL: missing main.py"; exit 1; }
[[ -f "$TDIR/work/out/stdout.txt" ]] || { echo "FAIL: missing stdout.txt"; exit 1; }
[[ -f "$TDIR/work/out/stderr.txt" ]] || { echo "FAIL: missing stderr.txt"; exit 1; }
[[ -f "$TDIR/work/out/artifacts/result.json" ]] || { echo "FAIL: missing result.json"; exit 1; }
[[ -d "$TDIR/work/fig" ]] || { echo "FAIL: missing work/fig"; exit 1; }
[[ -f "$TDIR/work/report.md" ]] || { echo "FAIL: missing report.md"; exit 1; }

[[ -d "$SDIR/work/src" ]] || { echo "FAIL: staged work/src missing"; exit 1; }
[[ -d "$SDIR/work/fig" ]] || { echo "FAIL: staged work/fig missing"; exit 1; }
[[ -f "$SDIR/work/report.md" ]] || { echo "FAIL: staged report.md missing"; exit 1; }
[[ -f "$PROMOTE_JSON" ]] || { echo "FAIL: missing PROMOTE.json"; exit 1; }

python3 - <<PY
import json
from pathlib import Path
p = Path("$PROMOTE_JSON")
obj = json.loads(p.read_text(encoding="utf-8"))
assert "command" not in obj, "PROMOTE.json must not include command"
assert "on_yes" not in obj, "PROMOTE.json must not include on_yes"
assert "on_no" not in obj, "PROMOTE.json must not include on_no"
prefixes = obj.get("allowed_dst_prefixes", [])
assert prefixes == ["USER/src/compute/", "USER/fig/compute/", "USER/reports/compute/"], "unexpected allowed_dst_prefixes"
mappings = obj.get("mappings", [])
assert len(mappings) == 3, f"expected 3 mappings, got {len(mappings)}"
PY

echo "PASS: compute artifact structure and promotion contract checks passed"
