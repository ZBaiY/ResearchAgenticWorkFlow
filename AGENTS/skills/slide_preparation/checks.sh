#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: checks.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
if [[ ! -d "$TDIR" ]]; then
  echo "Task folder not found: $TDIR" >&2
  exit 2
fi

if command -v git >/dev/null 2>&1; then
  BAD="$(git -C "$ROOT" status --porcelain USER GATE || true)"
  if [[ -n "$BAD" ]]; then
    echo "ERROR: USER/ or GATE/ changed:" >&2
    echo "$BAD" >&2
    exit 1
  fi
fi

required=(
  "$TDIR/review/slide_brief.md"
  "$TDIR/review/deck_outline.md"
  "$TDIR/review/speaker_notes.md"
  "$TDIR/review/figure_plan.md"
  "$TDIR/review/timing_plan.md"
  "$TDIR/logs/slide_preparation/resolved_request.json"
  "$TDIR/logs/slide_preparation/consent.json"
)

for f in "${required[@]}"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
done

if [[ -d "$TDIR/work/slides/scratch" || -d "$TDIR/work/slides/build" ]]; then
  echo "ERROR: scratch/build directories should be cleaned" >&2
  exit 1
fi

echo "CHECKS=ok TASK=$TASK_ID"
