#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: checks.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
[[ -d "$TDIR" ]] || { echo "Task folder missing: $TDIR" >&2; exit 2; }

req=(
  "$TDIR/review/literature_scout_report.md"
  "$TDIR/review/referee_risk.md"
  "$TDIR/review/refs.bib"
  "$TDIR/outputs/lit/raw_candidates.jsonl"
  "$TDIR/outputs/lit/retrieval_log.json"
  "$TDIR/logs/method.json"
  "$TDIR/logs/literature_scout/resolved_request.json"
)

for f in "${req[@]}"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
done

if command -v git >/dev/null 2>&1; then
  BAD="$(git -C "$ROOT" status --porcelain USER GATE || true)"
  [[ -z "$BAD" ]] || { echo "ERROR: USER/GATE modified" >&2; echo "$BAD" >&2; exit 1; }
fi

echo "CHECKS=ok TASK=$TASK_ID"
