#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

REQ="AGENTS/requests/regression/global_mode_promotion.md"
mkdir -p "$(dirname "$REQ")"
cat > "$REQ" <<'EOF'
# Request
goal:
regression for global mode promotion gating
EOF

PAPER_DIR="$(mktemp -d "/tmp/gmode_paper_XXXX")"
REFS_DIR="$(mktemp -d "/tmp/gmode_refs_XXXX")"
cat > "$PAPER_DIR/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Global Mode Promotion Test}
\begin{abstract}Profile generation test.</end{abstract}
\bibliography{references}
\cite{A2024}
\end{document}
EOF
cat > "$PAPER_DIR/references.bib" <<'EOF'
@article{A2024,title={Seed A},author={Alice One},year={2024}}
EOF
for i in 1 2 3; do
  cat > "$REFS_DIR/ref$i.txt" <<EOF
Title: Ref $i
Authors: Author $i
Abstract: text $i
arXiv:2401.0000$i
EOF
done
export PAPER_DIR REFS_DIR

# Case 1: default mode OFF.
TASK1="test_global_mode_off_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK1" --request "$REQ" >/tmp/gmode_off_start.out
OUT1="$(python3 - <<PY
import os, subprocess
env=dict(os.environ)
env["PAPER_PROFILE_USER_PAPER"]=os.environ["PAPER_DIR"]
env["PAPER_PROFILE_USER_REFS_FOR_SEEDS"]=os.environ["REFS_DIR"]
cp=subprocess.run(
    ["./bin/agenthub","run","--task","$TASK1","--yes"],
    stdin=subprocess.DEVNULL,
    text=True,
    capture_output=True,
    env=env,
)
print(f"RC={cp.returncode}")
print(cp.stdout)
print(cp.stderr)
PY
)"
printf '%s\n' "$OUT1"
grep -q 'RC=0' <<<"$OUT1" || { echo "FAIL: default mode run failed"; exit 1; }
grep -q 'AGENT_MODE=off' <<<"$OUT1" || { echo "FAIL: missing AGENT_MODE=off"; exit 1; }
grep -q 'AUTO_PROMOTE_USER=off' <<<"$OUT1" || { echo "FAIL: missing AUTO_PROMOTE_USER=off"; exit 1; }
grep -q 'PROMOTION_STATUS=READY' <<<"$OUT1" || { echo "FAIL: missing PROMOTION_STATUS=READY default mode"; exit 1; }
grep -q "PROMOTE_PLAN_PATH: GATE/staged/$TASK1/PROMOTE.md" <<<"$OUT1" || { echo "FAIL: missing PROMOTE_PLAN_PATH default mode"; exit 1; }
if grep -q 'PROMOTE_TO_USER? \[y/N\]' <<<"$OUT1"; then
  echo "FAIL: run must not prompt for promotion"
  exit 1
fi

# Case 2: global mode ON, non-interactive without explicit noninteractive write allowance.
TASK2="test_global_mode_on_blocked_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK2" --request "$REQ" >/tmp/gmode_on_blocked_start.out
OUT2="$(python3 - <<PY
import os, subprocess
env=dict(os.environ)
env["PAPER_PROFILE_USER_PAPER"]=os.environ["PAPER_DIR"]
env["PAPER_PROFILE_USER_REFS_FOR_SEEDS"]=os.environ["REFS_DIR"]
cp=subprocess.run(
    ["./bin/agenthub","run","--task","$TASK2","--yes","--agent-mode","--auto-promote-user"],
    stdin=subprocess.DEVNULL,
    text=True,
    capture_output=True,
    env=env,
)
print(f"RC={cp.returncode}")
print(cp.stdout)
print(cp.stderr)
PY
)"
printf '%s\n' "$OUT2"
grep -q 'RC=0' <<<"$OUT2" || { echo "FAIL: blocked mode run failed"; exit 1; }
grep -q 'AGENT_MODE=on' <<<"$OUT2" || { echo "FAIL: missing AGENT_MODE=on"; exit 1; }
grep -q 'AUTO_PROMOTE_USER=on' <<<"$OUT2" || { echo "FAIL: missing AUTO_PROMOTE_USER=on"; exit 1; }
grep -q 'PROMOTION_STATUS=READY' <<<"$OUT2" || { echo "FAIL: missing PROMOTION_STATUS=READY in blocked mode"; exit 1; }
grep -q "PROMOTE_PLAN_PATH: GATE/staged/$TASK2/PROMOTE.md" <<<"$OUT2" || { echo "FAIL: missing PROMOTE_PLAN_PATH in blocked mode"; exit 1; }

# Case 3: global mode ON + explicit noninteractive allowance => run still does not promote.
TASK3="test_global_mode_on_allowed_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK3" --request "$REQ" >/tmp/gmode_on_allowed_start.out
OUT3="$(python3 - <<PY
import os, subprocess
env=dict(os.environ)
env["PAPER_PROFILE_USER_PAPER"]=os.environ["PAPER_DIR"]
env["PAPER_PROFILE_USER_REFS_FOR_SEEDS"]=os.environ["REFS_DIR"]
cp=subprocess.run(
    ["./bin/agenthub","run","--task","$TASK3","--yes","--agent-mode","--auto-promote-user","--allow-user-write-noninteractive"],
    stdin=subprocess.DEVNULL,
    text=True,
    capture_output=True,
    env=env,
)
print(f"RC={cp.returncode}")
print(cp.stdout)
print(cp.stderr)
PY
)"
printf '%s\n' "$OUT3"
grep -q 'RC=0' <<<"$OUT3" || { echo "FAIL: allowed mode run failed"; exit 1; }
grep -q 'PROMOTION_STATUS=READY' <<<"$OUT3" || { echo "FAIL: missing PROMOTION_STATUS=READY in allowed mode"; exit 1; }
grep -q "PROMOTE_PLAN_PATH: GATE/staged/$TASK3/PROMOTE.md" <<<"$OUT3" || { echo "FAIL: missing PROMOTE_PLAN_PATH in allowed mode"; exit 1; }
if ls USER/manifest/promotion_receipts/${TASK3}_*.json >/dev/null 2>&1; then
  echo "FAIL: run should never create promotion receipt"
  exit 1
fi

echo "PASS: global mode promotion gating regression checks passed"
