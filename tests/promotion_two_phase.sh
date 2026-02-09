#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REQ="AGENTS/requests/regression/promotion_two_phase.md"
mkdir -p "$(dirname "$REQ")"
cat > "$REQ" <<'EOF'
# Request
goal:
promotion two-phase regression
EOF

TASK="test_promotion_two_phase_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK" --request "$REQ" >/tmp/promo_two_phase_start.out

PAPER_DIR="$(mktemp -d "/tmp/promo2_paper_XXXX")"
REFS_DIR="$(mktemp -d "/tmp/promo2_refs_XXXX")"
cat > "$PAPER_DIR/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Promotion Test}
\begin{abstract}Neutrino profile test.</end{abstract}
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
export PAPER_DIR REFS_DIR TASK

USER_META="USER/paper/meta/paper_profile.json"
BEFORE_HASH="missing"
if [[ -f "$USER_META" ]]; then
  BEFORE_HASH="$(shasum -a 256 "$USER_META" | awk '{print $1}')"
fi

OUT="$(python3 - <<'PY'
import os, subprocess
env=dict(os.environ)
env["PAPER_PROFILE_USER_PAPER"]=os.environ["PAPER_DIR"]
env["PAPER_PROFILE_USER_REFS_FOR_SEEDS"]=os.environ["REFS_DIR"]
cp=subprocess.run(
    ["./bin/agenthub","run","--task",os.environ["TASK"],"--yes"],
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
printf '%s\n' "$OUT"
grep -q 'RC=0' <<<"$OUT" || { echo "FAIL: run should succeed"; exit 1; }
grep -q 'AGENT_MODE=off' <<<"$OUT" || { echo "FAIL: expected AGENT_MODE=off by default"; exit 1; }
grep -q 'AUTO_PROMOTE_USER=off' <<<"$OUT" || { echo "FAIL: expected AUTO_PROMOTE_USER=off by default"; exit 1; }
grep -q 'PROMOTION_STATUS=READY' <<<"$OUT" || { echo "FAIL: missing PROMOTION_STATUS=READY"; exit 1; }
grep -q "PROMOTE_PLAN_PATH: GATE/staged/$TASK/PROMOTE.md" <<<"$OUT" || { echo "FAIL: missing PROMOTE_PLAN_PATH"; exit 1; }
grep -q 'PROMOTION_PENDING: true' <<<"$OUT" || { echo "FAIL: missing PROMOTION_PENDING true"; exit 1; }
grep -q 'PROMOTE_INSTRUCTIONS: Use the promote subcommand when ready\.' <<<"$OUT" || { echo "FAIL: missing PROMOTE_INSTRUCTIONS"; exit 1; }
if grep -q 'PROMOTE_TO_USER? \[y/N\]' <<<"$OUT"; then
  echo "FAIL: run must not print PROMOTE_TO_USER?"
  exit 1
fi
[[ -f "GATE/staged/$TASK/paper_profile_update/paper_profile.json" ]] || { echo "FAIL: staged payload missing"; exit 1; }
[[ -f "GATE/staged/$TASK/PROMOTE.json" ]] || { echo "FAIL: PROMOTE.json missing"; exit 1; }
[[ -f "GATE/staged/$TASK/PROMOTE.md" ]] || { echo "FAIL: PROMOTE.md missing"; exit 1; }

AFTER_HASH="missing"
if [[ -f "$USER_META" ]]; then
  AFTER_HASH="$(shasum -a 256 "$USER_META" | awk '{print $1}')"
fi
[[ "$BEFORE_HASH" == "$AFTER_HASH" ]] || { echo "FAIL: USER modified before explicit promotion"; exit 1; }

PROMO_SKIP="$(./bin/agenthub promote --task "$TASK" </dev/null)"
printf '%s\n' "$PROMO_SKIP"
grep -q 'PROMOTE_TO_USER=skipped reason=noninteractive_requires_explicit_flags' <<<"$PROMO_SKIP" || { echo "FAIL: expected noninteractive skip without explicit flags"; exit 1; }

PROMO_OUT="$(./bin/agenthub promote --task "$TASK" --yes --allow-user-write-noninteractive </dev/null)"
printf '%s\n' "$PROMO_OUT"
grep -q 'PROMOTE_TO_USER=done target=USER/paper/meta/paper_profile.json' <<<"$PROMO_OUT" || { echo "FAIL: missing done target output"; exit 1; }
ls USER/manifest/promotion_receipts/${TASK}_*.json >/dev/null 2>&1 || { echo "FAIL: missing promotion receipt"; exit 1; }

echo "PASS: two-phase promotion regression checks passed"
