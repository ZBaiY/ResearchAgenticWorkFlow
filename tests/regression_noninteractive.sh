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
Build paper profile for regression test.
EOF

PAPER_DIR="$(mktemp -d "/tmp/regression_paper_XXXX")"
REFS_DIR="$(mktemp -d "/tmp/regression_refs_XXXX")"
cat > "$PAPER_DIR/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Regression Paper}
\begin{abstract}Neutrino flavor conversion constraints from data.</end{abstract}
\bibliography{references}
\cite{Smith2024}
\end{document}
EOF
cat > "$PAPER_DIR/references.bib" <<'EOF'
@article{Smith2024,title={Flavor conversion constraints},author={Smith, A},year={2024},abstract={Flavor conversion constraints from neutrino data.}}
EOF
cat > "$REFS_DIR/ref1.txt" <<'EOF'
Neutrino flavor conversion signals
Authors: Alice Smith
Abstract: Signal extraction for neutrino flavor conversion in dark matter backgrounds.
arXiv:2404.11111
EOF
cat > "$REFS_DIR/ref2.txt" <<'EOF'
Dark matter neutrino interaction bounds
Authors: Bob Doe
Abstract: Bounds on dark matter neutrino interactions from oscillation data.
arXiv:2404.22222
EOF
cat > "$REFS_DIR/ref3.txt" <<'EOF'
Long-baseline phenomenology review
Authors: Carol Roe
Abstract: Review of long-baseline neutrino phenomenology and new physics tests.
arXiv:2404.33333
EOF
export PAPER_DIR
export REFS_DIR
USER_META="USER/paper/meta/paper_profile.json"
USER_META_HASH_BEFORE="missing"
if [[ -f "$USER_META" ]]; then
  USER_META_HASH_BEFORE="$(shasum -a 256 "$USER_META" | awk '{print $1}')"
fi

echo "[1/4] bart output check"
BART_OUT="$(./bart "please check draft metadata and suggest next steps")"
printf '%s\n' "$BART_OUT"
if printf '%s\n' "$BART_OUT" | rg -q "cat <<'EOF'|goal: TBD|constraints:[[:space:]]*- TBD"; then
  echo "FAIL: bart output contains verbose scaffold markers"
  exit 1
fi

echo "[2/4] create tasks"
RUN_TAG="$(date -u +%Y%m%dT%H%M%SZ)"
TASK_COMPUTE="$(./bin/agenthub start --skill compute_numerical --task-name "test_compute_noninteractive_${RUN_TAG}" --request "$REQ_DIR/compute_numerical.md" | sed -n 's/^TASK=\([^ ]*\).*/\1/p')"
TASK_REFEREE="$(./bin/agenthub start --skill referee_redteam_prl --task-name "test_referee_noninteractive_${RUN_TAG}" --request "$REQ_DIR/referee_redteam_prl.md" | sed -n 's/^TASK=\([^ ]*\).*/\1/p')"
TASK_PROFILE="$(./bin/agenthub start --skill paper_profile_update --task-name "test_profile_noninteractive_${RUN_TAG}" --request "$REQ_DIR/paper_profile_update.md" | sed -n 's/^TASK=\([^ ]*\).*/\1/p')"

echo "TASK_COMPUTE=$TASK_COMPUTE"
echo "TASK_REFEREE=$TASK_REFEREE"
echo "TASK_PROFILE=$TASK_PROFILE"

echo "[3/4] non-interactive run without flags defaults to --no (expect rc=0)"
export TASK_COMPUTE TASK_REFEREE TASK_PROFILE
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

for skill, tid in tasks.items():
    env = dict(os.environ)
    if skill == "paper_profile_update":
        env["PAPER_PROFILE_USER_PAPER"] = os.environ["PAPER_DIR"]
        env["PAPER_PROFILE_USER_REFS_FOR_SEEDS"] = os.environ["REFS_DIR"]
    cp = subprocess.run(
        ["./bin/agenthub", "run", "--task", tid],
        stdin=subprocess.DEVNULL,
        text=True,
        capture_output=True,
        env=env,
    )
    print(f"{skill}: rc={cp.returncode}")
    if cp.stdout.strip():
        print("stdout:")
        print(cp.stdout.strip())
    if cp.stderr.strip():
        print("stderr:")
        print(cp.stderr.strip())
    if cp.returncode != 0:
        print(f"FAIL: expected rc=0 for {skill}")
        sys.exit(1)
    if "Non-interactive shell" in cp.stderr:
        print(f"FAIL: unexpected non-interactive error for {skill}")
        sys.exit(1)

print("OK default --no policy works")
PY

if [[ -f "$USER_META" ]]; then
  USER_META_HASH_AFTER_STEP3="$(shasum -a 256 "$USER_META" | awk '{print $1}')"
else
  USER_META_HASH_AFTER_STEP3="missing"
fi
[[ "$USER_META_HASH_BEFORE" == "$USER_META_HASH_AFTER_STEP3" ]] || {
  echo "FAIL: USER changed during non-interactive default mode"
  exit 1
}

echo "[4/4] explicit --yes still deterministic"
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
    env = dict(os.environ)
    if skill == "paper_profile_update":
        env["PAPER_PROFILE_USER_PAPER"] = os.environ["PAPER_DIR"]
        env["PAPER_PROFILE_USER_REFS_FOR_SEEDS"] = os.environ["REFS_DIR"]
    cp = subprocess.run(
        ["./bin/agenthub", "run", "--task", tid, "--yes"],
        stdin=subprocess.DEVNULL,
        text=True,
        capture_output=True,
        env=env,
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
    out_path = expected_outputs[skill](tid)
    if not out_path.exists():
        print(f"FAIL: expected output missing for {skill}: {out_path}")
        sys.exit(1)

print("PASS: regression checks completed")
PY

if [[ -f "$USER_META" ]]; then
  USER_META_HASH_AFTER_STEP4="$(shasum -a 256 "$USER_META" | awk '{print $1}')"
else
  USER_META_HASH_AFTER_STEP4="missing"
fi
[[ "$USER_META_HASH_BEFORE" == "$USER_META_HASH_AFTER_STEP4" ]] || {
  echo "FAIL: USER changed during non-interactive --yes mode without promotion"
  exit 1
}
