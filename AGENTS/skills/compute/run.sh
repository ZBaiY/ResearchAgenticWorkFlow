#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="compute"
APPROVAL_SH="$ROOT/AGENTS/runtime/approval.sh"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
LOG_DIR="$TDIR/logs"
LOG_COMPUTE="$LOG_DIR/compute"
CMD_LOG="$LOG_DIR/commands.txt"
STDOUT_LOG="$LOG_DIR/compute.stdout.log"
STDERR_LOG="$LOG_DIR/compute.stderr.log"
GIT_STATUS_LOG="$LOG_DIR/git_status.txt"
RESOLVED_JSON="$LOG_COMPUTE/resolved_request.json"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi

source "$APPROVAL_SH"

mkdir -p "$LOG_DIR" "$LOG_COMPUTE" "$TDIR/review"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

log_cmd() { printf '%s\n' "$*" >> "$CMD_LOG"; }

backend="${COMPUTE_BACKEND:-}"
if [[ -z "$backend" && -f "$TDIR/work/compute_backend.txt" ]]; then
  backend="$(tr '[:upper:]' '[:lower:]' < "$TDIR/work/compute_backend.txt" | tr -d '[:space:]')"
fi

if [[ -z "$backend" ]]; then
  ans="$(approval_text "Generic compute skill is deprecated. Choose backend: [1] numerical-python [2] symbolic-mathematica: " "1")"
  case "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" in
    2|symbolic|mathematica|wolfram|compute_symbolic) backend="symbolic" ;;
    *) backend="numerical" ;;
  esac
fi

case "$backend" in
  python|numerical|compute_numerical) delegate_skill="compute_numerical" ;;
  wolfram|symbolic|mathematica|compute_symbolic) delegate_skill="compute_symbolic" ;;
  *) delegate_skill="compute_numerical" ;;
esac

cat > "$RESOLVED_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "deprecated": true,
  "selected_backend": "$delegate_skill",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF2

log_cmd "delegate $SKILL -> $delegate_skill"
bash "$ROOT/AGENTS/skills/$delegate_skill/run.sh" "$ROOT" "$TASK_ID"

{
  echo "# compute (deprecated) report"
  echo
  echo "- task_id: $TASK_ID"
  echo "- delegated_to: $delegate_skill"
  echo "- resolved_request: AGENTS/tasks/$TASK_ID/logs/compute/resolved_request.json"
  echo "- recommendation: use agentctl run $delegate_skill --task $TASK_ID directly"
} > "$TDIR/review/compute_skill_report.md"

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" status --porcelain > "$GIT_STATUS_LOG" || true
else
  echo "git not available or repo missing" > "$GIT_STATUS_LOG"
fi

echo "$SKILL delegated to $delegate_skill for task $TASK_ID"
