#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: checks.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
RESULT="$TDIR/outputs/compute/result.json"
LOGS="$TDIR/logs/compute"
CMDS="$LOGS/commands.txt"

[[ -f "$RESULT" ]] || { echo "Missing result.json"; exit 1; }
[[ -f "$CMDS" ]] || { echo "Missing commands.txt"; exit 1; }

if rg -q 'wolfram|math -script' "$CMDS"; then
  echo "Forbidden backend command found in numerical skill logs"
  exit 1
fi
if ! rg -q 'python3|python' "$CMDS"; then
  echo "No python command found for numerical run"
  exit 1
fi

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$ROOT" status --porcelain | rg -q '^(.. )?(USER/|GATE/)'; then
    echo "Detected modification under USER/ or GATE/"
    exit 1
  fi
fi

echo "compute_numerical checks: ok"
