#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REQ_DIR="AGENTS/requests/regression"
mkdir -p "$REQ_DIR"

cat > "$REQ_DIR/compute_numerical.md" <<'EOF'
# Request
Goal:
Run a minimal compute task.
EOF

cat > "$REQ_DIR/referee_redteam_prl.md" <<'EOF'
# Request
Goal:
Run a minimal referee pass.
EOF

cat > "$REQ_DIR/paper_profile_update.md" <<'EOF'
# Request
Goal:
TBD
Constraints:
- TBD
EOF

echo "[1/4] bart output check"
BART_OUT="$(./bart "please check draft metadata and suggest next steps")"
printf '%s\n' "$BART_OUT"
if printf '%s\n' "$BART_OUT" | rg -q "cat <<'EOF'|goal: TBD|constraints:[[:space:]]*- TBD"; then
  echo "FAIL: bart output contains verbose scaffold markers"
  exit 1
fi

echo "[2/4] create tasks"
TASK_COMPUTE="$(./bin/agenthub start --skill compute_numerical --task-name test_compute_noninteractive --request "$REQ_DIR/compute_numerical.md" | sed -n 's/^TASK=\([^ ]*\).*/\1/p')"
TASK_REFEREE="$(./bin/agenthub start --skill referee_redteam_prl --task-name test_referee_noninteractive --request "$REQ_DIR/referee_redteam_prl.md" | sed -n 's/^TASK=\([^ ]*\).*/\1/p')"
TASK_PROFILE="$(./bin/agenthub start --skill paper_profile_update --task-name test_profile_noninteractive --request "$REQ_DIR/paper_profile_update.md" | sed -n 's/^TASK=\([^ ]*\).*/\1/p')"

echo "TASK_COMPUTE=$TASK_COMPUTE"
echo "TASK_REFEREE=$TASK_REFEREE"
echo "TASK_PROFILE=$TASK_PROFILE"

echo "[3/4] non-interactive run without flags (expect rc=2)"
export TASK_COMPUTE TASK_REFEREE TASK_PROFILE
python3 - <<'PY'
import os
import subprocess
import sys

tasks = {
    "compute_numerical": os.environ["TASK_COMPUTE"],
    "referee_redteam_prl": os.environ["TASK_REFEREE"],
    "paper_profile_update": os.environ["TASK_PROFILE"],
}

for skill, tid in tasks.items():
    cp = subprocess.run(
        ["./bin/agenthub", "run", "--task", tid],
        stdin=subprocess.DEVNULL,
        text=True,
        capture_output=True,
    )
    print(f"{skill}: rc={cp.returncode}")
    if cp.stdout.strip():
        print("stdout:")
        print(cp.stdout.strip())
    if cp.stderr.strip():
        print("stderr:")
        print(cp.stderr.strip())
    if cp.returncode != 2:
        print(f"FAIL: expected rc=2 for {skill}")
        sys.exit(1)
    if "Non-interactive shell. Re-run with --yes or --no." not in cp.stderr:
        print(f"FAIL: missing non-interactive guidance for {skill}")
        sys.exit(1)
    if "EOFError" in (cp.stdout + cp.stderr):
        print(f"FAIL: EOFError detected for {skill}")
        sys.exit(1)
PY

echo "[4/4] non-interactive run with --yes (expect deterministic completion)"
python3 - <<'PY'
import os
import subprocess
import sys
from pathlib import Path

tasks = {
    "compute_numerical": os.environ["TASK_COMPUTE"],
    "referee_redteam_prl": os.environ["TASK_REFEREE"],
    "paper_profile_update": os.environ["TASK_PROFILE"],
}

expected_outputs = {
    "compute_numerical": lambda tid: Path(f"AGENTS/tasks/{tid}/review/compute_numerical_report.md"),
    "referee_redteam_prl": lambda tid: Path(f"AGENTS/tasks/{tid}/review/referee_report.md"),
    "paper_profile_update": lambda tid: Path(f"AGENTS/tasks/{tid}/review/paper_profile_update_report.md"),
}

for skill, tid in tasks.items():
    cp = subprocess.run(
        ["./bin/agenthub", "run", "--task", tid, "--yes"],
        stdin=subprocess.DEVNULL,
        text=True,
        capture_output=True,
    )
    print(f"{skill}: rc={cp.returncode}")
    if cp.stdout.strip():
        print("stdout:")
        print(cp.stdout.strip())
    if cp.stderr.strip():
        print("stderr:")
        print(cp.stderr.strip())
    if cp.returncode != 0:
        print(f"FAIL: expected rc=0 for {skill} with --yes")
        sys.exit(1)
    if "EOFError" in (cp.stdout + cp.stderr):
        print(f"FAIL: EOFError detected for {skill} with --yes")
        sys.exit(1)
    out_path = expected_outputs[skill](tid)
    if not out_path.exists():
        print(f"FAIL: expected output missing for {skill}: {out_path}")
        sys.exit(1)

print("PASS: regression checks completed")
PY
