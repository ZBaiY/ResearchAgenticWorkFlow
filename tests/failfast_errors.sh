#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REQ_DIR="AGENTS/requests/failfast"
mkdir -p "$REQ_DIR"

cat > "$REQ_DIR/minimal.md" <<'EOF'
# Request
Goal:
TBD
EOF

extract_task() {
  sed -n 's/^TASK=\([^ ]*\).*/\1/p' | head -n 1
}

assert_error_md() {
  local task="$1"
  local err="AGENTS/tasks/$task/review/error.md"
  [[ -f "$err" ]] || { echo "FAIL: missing $err"; exit 1; }
  rg -q '^ERROR_CLASS:' "$err" || { echo "FAIL: ERROR_CLASS missing"; exit 1; }
  rg -q '^ERROR_MESSAGE:' "$err" || { echo "FAIL: ERROR_MESSAGE missing"; exit 1; }
  rg -q '^WHERE:' "$err" || { echo "FAIL: WHERE missing"; exit 1; }
  rg -q '^PHASE:' "$err" || { echo "FAIL: PHASE missing"; exit 1; }
  rg -q '^LIKELY_CAUSE:' "$err" || { echo "FAIL: LIKELY_CAUSE missing"; exit 1; }
  rg -q '^IF_UNKNOWN_GUESS:' "$err" || { echo "FAIL: IF_UNKNOWN_GUESS missing"; exit 1; }
  rg -q '^NEXT_STEP:' "$err" || { echo "FAIL: NEXT_STEP missing"; exit 1; }
}

echo "[1/3] non-interactive prompt failure"
TASK1="$(./bin/agenthub start --skill compute_numerical --request "$REQ_DIR/minimal.md" | extract_task)"
export TASK1
python3 - <<'PY'
import os, subprocess, sys
cp = subprocess.run(["./bin/agenthub", "run", "--task", os.environ["TASK1"]], stdin=subprocess.DEVNULL, text=True, capture_output=True)
print(cp.stdout.strip())
print(cp.stderr.strip())
if cp.returncode == 0:
    print("FAIL: expected non-zero")
    sys.exit(1)
if "SEE=AGENTS/tasks/" not in cp.stderr:
    print("FAIL: missing SEE path")
    sys.exit(1)
PY
assert_error_md "$TASK1"
[[ ! -f "AGENTS/tasks/$TASK1/logs/compute/commands.txt" ]] || { echo "FAIL: skill logs should not exist"; exit 1; }

echo "[2/3] invalid flag combination failure"
TASK2="$(./bin/agenthub start --skill compute_numerical --request "$REQ_DIR/minimal.md" | extract_task)"
set +e
OUT2="$(./bin/agenthub run --task "$TASK2" --yes --no 2>&1)"
RC2=$?
set -e
printf '%s\n' "$OUT2"
[[ "$RC2" -ne 0 ]] || { echo "FAIL: expected non-zero"; exit 1; }
assert_error_md "$TASK2"
[[ ! -f "AGENTS/tasks/$TASK2/logs/compute/commands.txt" ]] || { echo "FAIL: skill should not run"; exit 1; }

echo "[3/3] missing skill subprocess failure"
TASK3="$(./bin/agenthub start --skill paper_profile_update --request "$REQ_DIR/minimal.md" | extract_task)"
set +e
OUT3="$(./bin/agenthub run --task "$TASK3" --skill does_not_exist --yes 2>&1)"
RC3=$?
set -e
printf '%s\n' "$OUT3"
[[ "$RC3" -ne 0 ]] || { echo "FAIL: expected non-zero"; exit 1; }
assert_error_md "$TASK3"
[[ ! -d "GATE/staged/$TASK3" ]] || { echo "FAIL: should not stage after failure"; exit 1; }

echo "PASS: fail-fast error handling tests passed"
