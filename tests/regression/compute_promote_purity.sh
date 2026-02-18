#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

REQ="AGENTS/requests/regression/compute_promote_purity.md"
mkdir -p "$(dirname "$REQ")"
cat > "$REQ" <<'EOF'
# Request

Goal:
Promote purity regression for compute_numerical.

Inputs (JSON):
```json
{
  "goal": "Promote purity regression for compute_numerical.",
  "inputs": {
    "mode": "quadratic_scan",
    "x_values": [0, 1, 2],
    "coefficients": {"a": 1.0, "b": 1.0, "c": 1.0},
    "make_plot": false
  },
  "expected_outputs": {
    "result_file": "result.json"
  },
  "constraints": [
    "No network"
  ],
  "preferred_formats": [
    "json"
  ]
}
```
EOF

TASK="test_compute_promote_purity_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill compute_numerical --task-name "$TASK" --request "$REQ" >/tmp/test_compute_promote_purity_start.out
./bin/agenthub request-set --task "$TASK" --field goal --value "Promote purity regression for compute_numerical." >/tmp/test_compute_promote_purity_goal.out
./bin/agenthub request-set --task "$TASK" --field inputs --value '{"mode":"quadratic_scan","x_values":[0,1,2],"coefficients":{"a":1.0,"b":1.0,"c":1.0},"make_plot":false}' >/tmp/test_compute_promote_purity_inputs.out
./bin/agenthub request-set --task "$TASK" --field expected_outputs --value '{"result_file":"result.json"}' >/tmp/test_compute_promote_purity_expected.out
./bin/agenthub request-set --task "$TASK" --field constraints --value '["No network"]' >/tmp/test_compute_promote_purity_constraints.out
./bin/agenthub request-set --task "$TASK" --field preferred_formats --value '["json"]' >/tmp/test_compute_promote_purity_formats.out
./bin/agenthub run --task "$TASK" --yes </dev/null >/tmp/test_compute_promote_purity_run.out

PROMOTE_JSON="GATE/staged/$TASK/PROMOTE.json"
[[ -f "$PROMOTE_JSON" ]] || { echo "FAIL: missing PROMOTE.json"; exit 1; }
BACKUP="$(mktemp "/tmp/compute_promote_purity.XXXXXX.json")"
cp "$PROMOTE_JSON" "$BACKUP"

echo "[case a] src boundary violation is rejected"
python3 - <<PY
import json
from pathlib import Path
p = Path("$PROMOTE_JSON")
obj = json.loads(p.read_text(encoding="utf-8"))
obj["mappings"][0]["src"] = "AGENTS/tasks/$TASK/request.md"
p.write_text(json.dumps(obj, indent=2), encoding="utf-8")
PY
set +e
OUT_A="$(./bin/agenthub promote --task "$TASK" --yes --allow-user-write-noninteractive </dev/null 2>&1)"
RC_A=$?
set -e
printf '%s\n' "$OUT_A"
[[ "$RC_A" -ne 0 ]] || { echo "FAIL: expected promote failure for invalid src"; exit 1; }
grep -Eq 'mapping_validation_error: src outside staged task boundary' <<<"$OUT_A" || {
  echo "FAIL: missing src boundary failure message"
  exit 1
}

cp "$BACKUP" "$PROMOTE_JSON"

echo "[case b] dst allowlist violation is rejected"
python3 - <<PY
import json
from pathlib import Path
p = Path("$PROMOTE_JSON")
obj = json.loads(p.read_text(encoding="utf-8"))
obj["mappings"][0]["dst"] = "USER/paper/meta/hijack.json"
p.write_text(json.dumps(obj, indent=2), encoding="utf-8")
PY
set +e
OUT_B="$(./bin/agenthub promote --task "$TASK" --yes --allow-user-write-noninteractive </dev/null 2>&1)"
RC_B=$?
set -e
printf '%s\n' "$OUT_B"
[[ "$RC_B" -ne 0 ]] || { echo "FAIL: expected promote failure for invalid dst"; exit 1; }
grep -Eq 'mapping_validation_error: dst outside allowed USER boundary' <<<"$OUT_B" || {
  echo "FAIL: missing dst boundary failure message"
  exit 1
}

echo "PASS: compute promote purity boundary checks passed"
