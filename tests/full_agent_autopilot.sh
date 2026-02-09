#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

assert_contains() {
  local text="$1"
  local pat="$2"
  if ! printf '%s\n' "$text" | rg -q "$pat"; then
    echo "FAIL: missing pattern: $pat" >&2
    exit 1
  fi
}

snapshot_tasks() {
  find AGENTS/tasks -mindepth 1 -maxdepth 1 -type d -print | sort
}

PAPER_DIR="$(mktemp -d "/tmp/fullagent_paper_XXXX")"
REFS_DIR="$(mktemp -d "/tmp/fullagent_refs_XXXX")"
cat > "$PAPER_DIR/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Autopilot Paper}
\begin{abstract}Dark matter neutrino coupling test manuscript.\end{abstract}
\bibliography{references}
\cite{Smith2024}
\end{document}
EOF
cat > "$PAPER_DIR/references.bib" <<'EOF'
@article{Smith2024,title={Dark matter neutrino coupling},author={Smith, A},year={2024},abstract={Dark matter neutrino coupling phenomenology.}}
EOF
cat > "$REFS_DIR/ref1.txt" <<'EOF'
Dark matter neutrino coupling analysis
Authors: Alice Smith
Abstract: Coupling analysis in neutrino oscillation channels.
arXiv:2405.11111
EOF
cat > "$REFS_DIR/ref2.txt" <<'EOF'
Oscillation phase shifts from ultralight backgrounds
Authors: Bob Doe
Abstract: Ultralight backgrounds produce oscillation phase shifts.
arXiv:2405.22222
EOF
cat > "$REFS_DIR/ref3.txt" <<'EOF'
Phenomenological constraints on flavor conversion
Authors: Carol Roe
Abstract: Constraints on flavor conversion from precision neutrino datasets.
arXiv:2405.33333
EOF

echo "[1/3] non-full-agent remains suggest-only with pick required"
before_tasks="$(snapshot_tasks)"
OUT1="$(./bart "update project meta from draft")"
after_tasks="$(snapshot_tasks)"
printf '%s\n' "$OUT1"
assert_contains "$OUT1" '^Pick required: yes$'
if [[ "$before_tasks" != "$after_tasks" ]]; then
  echo "FAIL: default mode should not create tasks" >&2
  exit 1
fi

echo "[2/3] full-agent auto start/run succeeds non-interactively"
OUT2="$(PAPER_PROFILE_USER_PAPER="$PAPER_DIR" PAPER_PROFILE_USER_REFS_FOR_SEEDS="$REFS_DIR" ./bart --full-agent "update project meta from draft" < /dev/null)"
printf '%s\n' "$OUT2"
assert_contains "$OUT2" '^MODE=FULL_AGENT$'
assert_contains "$OUT2" '^RUN=ok$'
assert_contains "$OUT2" '^STAGED_TO_GATE=yes$'

TASK2="$(printf '%s\n' "$OUT2" | sed -n 's/^TASK=//p' | head -n1)"
if [[ -z "$TASK2" ]]; then
  echo "FAIL: missing TASK in full-agent output" >&2
  exit 1
fi

if [[ ! -d "AGENTS/tasks/$TASK2" ]]; then
  echo "FAIL: missing task dir AGENTS/tasks/$TASK2" >&2
  exit 1
fi

if [[ -z "$(find "AGENTS/tasks/$TASK2/review" -maxdepth 1 -type f -name '*.md' -print -quit)" ]]; then
  echo "FAIL: expected review report in AGENTS/tasks/$TASK2/review/" >&2
  exit 1
fi

if printf '%s\n' "$OUT2" | rg -q 'Proceed with run\?|EOFError'; then
  echo "FAIL: unexpected interactive prompt markers in full-agent output" >&2
  exit 1
fi

echo "[3/3] low-confidence full-agent still runs with risk marker"
OUT3="$(PAPER_PROFILE_USER_PAPER="$PAPER_DIR" PAPER_PROFILE_USER_REFS_FOR_SEEDS="$REFS_DIR" ./bart --full-agent "do something totally unrelated blahblah" < /dev/null)"
printf '%s\n' "$OUT3"
assert_contains "$OUT3" '^MODE=FULL_AGENT$'
assert_contains "$OUT3" '^WARN=NO_GOOD_SKILL_MATCH$'
assert_contains "$OUT3" '^RISK=HIGH$'

TASK3="$(printf '%s\n' "$OUT3" | sed -n 's/^TASK=//p' | head -n1)"
if [[ -z "$TASK3" || ! -d "AGENTS/tasks/$TASK3" ]]; then
  echo "FAIL: low-confidence full-agent did not create task" >&2
  exit 1
fi

echo "PASS: full-agent autopilot regression checks passed"
