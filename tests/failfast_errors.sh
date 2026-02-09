#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REQ_DIR="AGENTS/requests/failfast"
mkdir -p "$REQ_DIR"

cat > "$REQ_DIR/minimal.md" <<'EOF'
# Request
Goal:
Build paper profile.
EOF

extract_task() {
  sed -n 's/^TASK=\([^ ]*\).*/\1/p' | head -n 1
}

assert_error_md() {
  local task="$1"
  local err="AGENTS/tasks/$task/review/error.md"
  [[ -f "$err" ]] || { echo "FAIL: missing $err"; exit 1; }
  rg -q '^error_code: PROFILE_REQUIREMENTS_NOT_MET$' "$err" || { echo "FAIL: error_code missing"; exit 1; }
  rg -q '^missing: ' "$err" || { echo "FAIL: missing list missing"; exit 1; }
  rg -q '^online_lookup: ' "$err" || { echo "FAIL: online_lookup missing"; exit 1; }
  rg -q '^inputs_scanned: ' "$err" || { echo "FAIL: inputs_scanned missing"; exit 1; }
  rg -q '^next_actions:' "$err" || { echo "FAIL: next_actions missing"; exit 1; }
  rg -q '^stop_reason: ' "$err" || { echo "FAIL: stop_reason missing"; exit 1; }
}

echo "[1/4] invalid flag combination failure still failfast"
RUN_TAG="$(date -u +%Y%m%dT%H%M%SZ)"
TASK1="$(./bin/agenthub start --skill compute_numerical --task-name "test_failfast_compute_${RUN_TAG}" --request "$REQ_DIR/minimal.md" | extract_task)"
set +e
OUT1="$(./bin/agenthub run --task "$TASK1" --yes --no 2>&1)"
RC1=$?
set -e
printf '%s\n' "$OUT1"
[[ "$RC1" -ne 0 ]] || { echo "FAIL: expected non-zero"; exit 1; }
rg -q '^SEE=AGENTS/tasks/.*/review/error.md$' <<<"$OUT1" || { echo "FAIL: missing SEE"; exit 1; }

echo "[2/4] missing skill subprocess failure"
TASK2="$(./bin/agenthub start --skill paper_profile_update --task-name "test_failfast_missing_skill_${RUN_TAG}" --request "$REQ_DIR/minimal.md" | extract_task)"
set +e
OUT2="$(./bin/agenthub run --task "$TASK2" --skill does_not_exist --yes 2>&1)"
RC2=$?
set -e
printf '%s\n' "$OUT2"
[[ "$RC2" -ne 0 ]] || { echo "FAIL: expected non-zero"; exit 1; }
rg -q '^SEE=AGENTS/tasks/.*/review/error.md$' <<<"$OUT2" || { echo "FAIL: missing SEE"; exit 1; }

echo "[3/4] paper_profile_update failfast: minimal tex, no bib/references"
PAPER_A="$(mktemp -d /tmp/failfast_paper_a_XXXX)"
cat > "$PAPER_A/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Minimal Draft}
\begin{abstract}Test draft text only.</end{abstract}
\section{Introduction}This is minimal.
\end{document}
EOF
TASK3="$(./bin/agenthub start --skill paper_profile_update --task-name "test_failfast_profile_a_${RUN_TAG}" --request "$REQ_DIR/minimal.md" | extract_task)"
set +e
OUT3="$(PAPER_PROFILE_USER_PAPER="$PAPER_A" ./bin/agenthub run --task "$TASK3" 2>&1)"
RC3=$?
set -e
printf '%s\n' "$OUT3"
[[ "$RC3" -ne 0 ]] || { echo "FAIL: expected non-zero"; exit 1; }
rg -q '^MISSING=' <<<"$OUT3" || { echo "FAIL: expected MISSING line in stderr"; exit 1; }
assert_error_md "$TASK3"
ERR3="AGENTS/tasks/$TASK3/review/error.md"
rg -q 'seed_papers\(complete>=3\)' "$ERR3" || { echo "FAIL: missing seed requirement in error.md"; exit 1; }

echo "[4/4] paper_profile_update failfast: bib without abstracts and online_lookup=false"
PAPER_B="$(mktemp -d /tmp/failfast_paper_b_XXXX)"
cat > "$PAPER_B/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Draft With Bib}
\begin{abstract}Neutrino oscillation draft content.</end{abstract}
\bibliography{refs}
\cite{NoAbs2024}
\end{document}
EOF
cat > "$PAPER_B/refs.bib" <<'EOF'
@article{NoAbs2024,
  title={A Relevant Title},
  author={Doe, Jane},
  year={2024},
  eprint={2401.12345},
  archivePrefix={arXiv}
}
EOF
TASK4="$(./bin/agenthub start --skill paper_profile_update --task-name "test_failfast_profile_b_${RUN_TAG}" --request "$REQ_DIR/minimal.md" | extract_task)"
set +e
OUT4="$(PAPER_PROFILE_USER_PAPER="$PAPER_B" ./bin/agenthub run --task "$TASK4" 2>&1)"
RC4=$?
set -e
printf '%s\n' "$OUT4"
[[ "$RC4" -ne 0 ]] || { echo "FAIL: expected non-zero"; exit 1; }
assert_error_md "$TASK4"
ERR4="AGENTS/tasks/$TASK4/review/error.md"
rg -q 'seed_papers\(complete>=3\)' "$ERR4" || { echo "FAIL: missing seed requirement in error.md"; exit 1; }
rg -q 'online_lookup=true' "$ERR4" || { echo "FAIL: expected online_lookup=true guidance in next_actions"; exit 1; }

echo "PASS: fail-fast error handling tests passed"
