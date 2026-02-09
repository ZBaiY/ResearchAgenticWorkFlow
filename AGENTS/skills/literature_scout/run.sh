#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="literature_scout"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
LOGS="$TDIR/logs"
OUT_LIT="$TDIR/outputs/lit"
REVIEW="$TDIR/review"
STDOUT_LOG="$LOGS/${SKILL}.stdout.log"
STDERR_LOG="$LOGS/${SKILL}.stderr.log"
CMD_LOG="$LOGS/commands.txt"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi
if [[ ! -f "$TDIR/request.md" ]]; then
  echo "Missing required request.md: $TDIR/request.md" >&2
  exit 2
fi

mkdir -p "$LOGS" "$OUT_LIT" "$REVIEW"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"
: > "$CMD_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

echo "python3 AGENTS/skills/literature_scout/run.py $ROOT $TASK_ID" >> "$CMD_LOG"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/AGENTS/skills/literature_scout/run.py" "$ROOT" "$TASK_ID"
elif command -v python >/dev/null 2>&1; then
  python "$ROOT/AGENTS/skills/literature_scout/run.py" "$ROOT" "$TASK_ID"
else
  echo "Python runtime unavailable for literature_scout" >> "$STDERR_LOG"
  cat > "$REVIEW/literature_scout_report.md" <<EOF2
# Literature Scout Report

- task_id: $TASK_ID
- status: backend_unavailable
- note: Python runtime is unavailable; retrieval was not executed.
- action: install Python and rerun the task.
EOF2
  cat > "$OUT_LIT/retrieval_log.json" <<EOF2
[
  {
    "method": "init",
    "ok": false,
    "error": "python runtime unavailable",
    "ts": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  }
]
EOF2
  exit 1
fi

bash "$ROOT/AGENTS/runtime/stage_to_gate.sh" "$ROOT" "$TASK_ID" "$SKILL"

echo "$SKILL completed for task $TASK_ID"
