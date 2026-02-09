#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: checks.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
WORK_COMPUTE="$TDIR/work/compute"
SPEC="$WORK_COMPUTE/spec.yaml"
MAIN_PY="$WORK_COMPUTE/main.py"
MAIN_WL="$WORK_COMPUTE/main.wl"

[[ -d "$TDIR" ]] || { echo "Task not found: $TDIR"; exit 1; }
[[ -f "$SPEC" ]] || { echo "Missing spec.yaml"; exit 1; }
if [[ ! -f "$MAIN_PY" && ! -f "$MAIN_WL" ]]; then
  echo "Missing backend entrypoint (main.py or main.wl)"
  exit 1
fi

echo "compute skill checks: ok"
