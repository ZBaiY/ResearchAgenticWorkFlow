#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="slide_preparation"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
LOG_DIR="$TDIR/logs"
LOG_SKILL="$LOG_DIR/slide_preparation"
STDOUT_LOG="$LOG_DIR/${SKILL}.stdout.log"
STDERR_LOG="$LOG_DIR/${SKILL}.stderr.log"
CMD_LOG="$LOG_DIR/commands.txt"
REQ_FILE="$TDIR/request.md"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi
if [[ ! -f "$REQ_FILE" ]]; then
  echo "Missing required input: $REQ_FILE" >&2
  exit 2
fi

mkdir -p "$LOG_DIR" "$LOG_SKILL" "$TDIR/review" "$TDIR/work/slides/scratch" "$TDIR/work/slides/build"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"
: > "$CMD_LOG"

echo "python3 AGENTS/skills/slide_preparation/run.py $ROOT $TASK_ID" >> "$CMD_LOG"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/AGENTS/skills/slide_preparation/run.py" "$ROOT" "$TASK_ID" >> "$STDOUT_LOG" 2>> "$STDERR_LOG"
elif command -v python >/dev/null 2>&1; then
  python "$ROOT/AGENTS/skills/slide_preparation/run.py" "$ROOT" "$TASK_ID" >> "$STDOUT_LOG" 2>> "$STDERR_LOG"
else
  echo "Python runtime unavailable" >> "$STDERR_LOG"
  cat > "$TDIR/review/slide_brief.md" <<EOF2
# Slide Brief

- task_id: $TASK_ID
- skill: $SKILL
- status: backend_unavailable
- note: Python runtime unavailable; slide skeleton generation did not run.
- action: install Python and rerun this task.
EOF2
  exit 1
fi

if command -v git >/dev/null 2>&1; then
  git -C "$ROOT" status --porcelain > "$LOG_DIR/git_status.txt" || true
fi

bash "$ROOT/AGENTS/runtime/stage_to_gate.sh" "$ROOT" "$TASK_ID" "$SKILL"

echo "$SKILL completed for task $TASK_ID"
