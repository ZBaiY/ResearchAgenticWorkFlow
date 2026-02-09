#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

REQ="AGENTS/requests/regression/run_output_no_promotion_prompt.md"
mkdir -p "$(dirname "$REQ")"
cat > "$REQ" <<'EOF'
# Request
goal:
regression for non-interactive run output and no promotion prompt
EOF

TASK="test_run_output_no_promo_$(date -u +%Y%m%dT%H%M%SZ)"
START_OUT="$(./bart "update metadata" --pick 1 --start)"
printf '%s\n' "$START_OUT"
if grep -q 'PROMOTE_TO_USER? \[y/N\]' <<<"$START_OUT"; then
  echo "FAIL: bart --start must not print PROMOTE_TO_USER?"
  exit 1
fi

# derive task id from bart start output
TASK_FROM_START="$(printf '%s\n' "$START_OUT" | sed -n 's/^TASK=//p' | head -n1 | awk '{print $1}')"
if [[ -n "$TASK_FROM_START" ]]; then
  TASK="$TASK_FROM_START"
else
  # fallback dedicated start path for deterministic run check
  ./bin/agenthub start --skill paper_profile_update --task-name "$TASK" --request "$REQ" >/tmp/run_output_no_promo_start.out
fi

PAPER_DIR="$(mktemp -d "/tmp/run_output_no_promo_paper_XXXX")"
REFS_DIR="$(mktemp -d "/tmp/run_output_no_promo_refs_XXXX")"
cat > "$PAPER_DIR/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Run Output Contract}
\begin{abstract}Test run output behavior.</end{abstract}
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

USER_META="USER/paper/meta/paper_profile.json"
BEFORE_HASH="missing"
if [[ -f "$USER_META" ]]; then
  BEFORE_HASH="$(shasum -a 256 "$USER_META" | awk '{print $1}')"
fi

RUN_OUT="$(PAPER_PROFILE_USER_PAPER="$PAPER_DIR" PAPER_PROFILE_USER_REFS_FOR_SEEDS="$REFS_DIR" ./bin/agenthub run --task "$TASK" --yes </dev/null)"
printf '%s\n' "$RUN_OUT"

if grep -q 'PROMOTE_TO_USER? \[y/N\]' <<<"$RUN_OUT"; then
  echo "FAIL: run must not print PROMOTE_TO_USER?"
  exit 1
fi

if grep -Eq '^(NEXT=|NEXT_RUN=|NEXT_PROMOTE=|PROMOTION_COMMAND=|RUN=|CMD=|SHELL=|\./|bash )' <<<"$RUN_OUT"; then
  echo "FAIL: run output contains forbidden executable token"
  exit 1
fi

grep -q 'PROMOTION_STATUS=READY' <<<"$RUN_OUT" || { echo "FAIL: missing PROMOTION_STATUS=READY"; exit 1; }
grep -q 'PROMOTION_PENDING: true' <<<"$RUN_OUT" || { echo "FAIL: missing PROMOTION_PENDING"; exit 1; }
grep -q 'PROMOTE_INSTRUCTIONS: Use the promote subcommand when ready\.' <<<"$RUN_OUT" || { echo "FAIL: missing PROMOTE_INSTRUCTIONS"; exit 1; }
grep -q "PROMOTE_PLAN_PATH: GATE/staged/$TASK/PROMOTE.md" <<<"$RUN_OUT" || { echo "FAIL: missing PROMOTE_PLAN_PATH"; exit 1; }

AFTER_HASH="missing"
if [[ -f "$USER_META" ]]; then
  AFTER_HASH="$(shasum -a 256 "$USER_META" | awk '{print $1}')"
fi
[[ "$BEFORE_HASH" == "$AFTER_HASH" ]] || { echo "FAIL: USER modified during run"; exit 1; }

[[ -f "GATE/staged/$TASK/PROMOTE.md" ]] || { echo "FAIL: missing PROMOTE.md"; exit 1; }

echo "PASS: run output has no promotion prompt or executable tokens"
