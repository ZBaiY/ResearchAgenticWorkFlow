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

if command -v git >/dev/null 2>&1; then
  BAD="$(git -C "$ROOT" status --porcelain USER GATE || true)"
  [[ -z "$BAD" ]] || { echo "ERROR: USER/GATE modified" >&2; echo "$BAD" >&2; exit 1; }
fi

echo "CHECKS=ok TASK=$TASK_ID"
