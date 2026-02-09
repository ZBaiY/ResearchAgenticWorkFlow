#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REQ_DIR="AGENTS/requests/noninteractive_contract"
mkdir -p "$REQ_DIR"

cat > "$REQ_DIR/paper_profile_update.md" <<'EOF'
# Request
goal:
validate deterministic non-interactive run
constraints:
- Do not modify USER; stage only to GATE; promotion is manual
inputs:
- USER/paper/**/*.tex
EOF

TASK_NAME="test_noninteractive_contract_$(date -u +%Y%m%dT%H%M%SZ)"
TASK_ID="$(./bin/agenthub start --skill paper_profile_update --task-name "$TASK_NAME" --request "$REQ_DIR/paper_profile_update.md" | sed -n 's/^TASK=\([^ ]*\).*/\1/p')"
export TASK_ID
echo "TASK_ID=$TASK_ID"

PAPER_DIR="$(mktemp -d "/tmp/noninteractive_paper_XXXX")"
REFS_DIR="$(mktemp -d "/tmp/noninteractive_refs_XXXX")"
cat > "$PAPER_DIR/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Test Paper}
\begin{abstract}Neutrino oscillation in dark matter background.\end{abstract}
\bibliography{references}
\cite{Smith2024}
\end{document}
EOF
cat > "$PAPER_DIR/references.bib" <<'EOF'
@article{Smith2024,title={Neutrino oscillation signatures},author={Smith, A},year={2024},abstract={Neutrino oscillation signatures in dark matter backgrounds.}}
EOF
cat > "$REFS_DIR/ref1.txt" <<'EOF'
Neutrino oscillation in dark matter background
Authors: Alice Smith
Abstract: This paper studies neutrino flavor conversion in dark matter.
arXiv:2401.11111
EOF
cat > "$REFS_DIR/ref2.txt" <<'EOF'
Flavor conversion constraints from precision data
Authors: Bob Doe
Abstract: Precision neutrino experiments constrain dark-sector couplings.
arXiv:2402.22222
EOF
cat > "$REFS_DIR/ref3.txt" <<'EOF'
Ultralight dark matter induced oscillation phases
Authors: Carol Roe
Abstract: Ultralight dark matter induces phase shifts in neutrino propagation.
arXiv:2403.33333
EOF
export PAPER_DIR
export REFS_DIR

echo "[1/2] run without --yes/--no in non-interactive shell (expect failure)"
set +e
OUT1="$(python3 - <<'PY'
import os
import subprocess

tid = os.environ["TASK_ID"]
cp = subprocess.run(
    ["./bin/agenthub", "run", "--task", tid],
    stdin=subprocess.DEVNULL,
    text=True,
    capture_output=True,
)
print(f"RC={cp.returncode}")
if cp.stdout.strip():
    print("STDOUT:")
    print(cp.stdout.strip())
if cp.stderr.strip():
    print("STDERR:")
    print(cp.stderr.strip())
PY
)"
RC1=$?
set -e
printf '%s\n' "$OUT1"
if ! printf '%s\n' "$OUT1" | rg -q 'RC=2'; then
  echo "FAIL: expected RC=2 without --yes/--no" >&2
  exit 1
fi
if ! printf '%s\n' "$OUT1" | rg -q 'Non-interactive shell\. Re-run with --yes or --no\.'; then
  echo "FAIL: missing non-interactive guidance" >&2
  exit 1
fi

echo "[2/2] run with --yes in non-interactive shell (expect success)"
OUT2="$(python3 - <<'PY'
import os
import subprocess
from pathlib import Path

tid = os.environ["TASK_ID"]
cp = subprocess.run(
    ["./bin/agenthub", "run", "--task", tid, "--yes"],
    stdin=subprocess.DEVNULL,
    text=True,
    capture_output=True,
    timeout=90,
    env={
        **os.environ,
        "PAPER_PROFILE_USER_PAPER": os.environ["PAPER_DIR"],
        "PAPER_PROFILE_USER_REFS_FOR_SEEDS": os.environ["REFS_DIR"],
    },
)
print(f"RC={cp.returncode}")
if cp.stdout.strip():
    print("STDOUT:")
    print(cp.stdout.strip())
if cp.stderr.strip():
    print("STDERR:")
    print(cp.stderr.strip())
report = Path(f"AGENTS/tasks/{tid}/review/paper_profile_update_report.md")
print(f"REPORT_EXISTS={report.exists()}")
PY
)"
printf '%s\n' "$OUT2"
if ! printf '%s\n' "$OUT2" | rg -q 'RC=0'; then
  echo "FAIL: expected RC=0 with --yes" >&2
  exit 1
fi
if ! printf '%s\n' "$OUT2" | rg -q 'REPORT_EXISTS=True'; then
  echo "FAIL: expected paper_profile_update report output" >&2
  exit 1
fi
if printf '%s\n' "$OUT2" | rg -q 'Non-interactive shell\. Re-run with --yes or --no\.'; then
  echo "FAIL: --yes path re-emitted non-interactive error" >&2
  exit 1
fi

echo "PASS: non-interactive contract checks passed"
