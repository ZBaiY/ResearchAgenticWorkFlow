#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      TASK_ID="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$TASK_ID" ]]; then
  echo "Usage: bash AGENTS/runtime/compute_runner.sh --task <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/tasks/$TASK_ID"
LOG_DIR="$TDIR/logs/compute"
mkdir -p "$LOG_DIR"

STDOUT_LOG="$LOG_DIR/runner.stdout.log"
STDERR_LOG="$LOG_DIR/runner.stderr.log"
CMD_LOG="$LOG_DIR/commands.txt"

: > "$STDOUT_LOG"
: > "$STDERR_LOG"
: > "$CMD_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

echo "python3 $ROOT/runtime/compute_runner.py --root $ROOT --task $TASK_ID" >> "$CMD_LOG"
python3 "$ROOT/runtime/compute_runner.py" --root "$ROOT" --task "$TASK_ID"
