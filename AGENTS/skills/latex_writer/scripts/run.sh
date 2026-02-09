#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="latex_writer"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
USER_PAPER="$ROOT/USER/paper"
SHADOW_ROOT="$TDIR/work/paper_shadow"
SHADOW_PAPER="$SHADOW_ROOT/paper"
REVIEW_DIR="$TDIR/review"
PATCH_DIR="$TDIR/deliverable/patchset"
LOG_DIR="$TDIR/logs"
REPORT="$REVIEW_DIR/${SKILL}_report.md"
PATCH_FILE="$PATCH_DIR/patch.diff"
MANIFEST="$PATCH_DIR/files_manifest.json"
CMD_LOG="$LOG_DIR/commands.txt"
STDOUT_LOG="$LOG_DIR/${SKILL}.stdout.log"
STDERR_LOG="$LOG_DIR/${SKILL}.stderr.log"
GIT_STATUS_LOG="$LOG_DIR/git_status.txt"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi

mkdir -p "$REVIEW_DIR" "$PATCH_DIR" "$LOG_DIR" "$SHADOW_ROOT"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

run_cmd() {
  printf '%s\n' "$*" >> "$CMD_LOG"
  "$@"
}

if [[ ! -d "$USER_PAPER" ]]; then
  echo "Missing required input directory: $USER_PAPER" >&2
  exit 2
fi

run_cmd rsync -a --delete "$USER_PAPER/" "$SHADOW_PAPER/"

cat > "$REPORT" <<EOF2
# latex_writer Report

- task_id: $TASK_ID
- skill: $SKILL
- input_paper_root: USER/paper
- shadow_root: AGENTS/tasks/$TASK_ID/work/paper_shadow/paper

## Summary
- Placeholder run with deterministic, safe behavior.
- No LLM content rewrite was attempted.

## Edit Actions
EOF2

PLACEHOLDER_COMMENT='% latex_writer: placeholder run - no edits applied'
MAIN_TEX="$SHADOW_PAPER/main.tex"
EDITED=false

if [[ -f "$MAIN_TEX" ]]; then
  FIRST_LINE="$(head -n 1 "$MAIN_TEX" || true)"
  if [[ "$FIRST_LINE" != "$PLACEHOLDER_COMMENT" ]]; then
    TMP_FILE="$MAIN_TEX.tmp.$$"
    {
      printf '%s\n' "$PLACEHOLDER_COMMENT"
      cat "$MAIN_TEX"
    } > "$TMP_FILE"
    mv "$TMP_FILE" "$MAIN_TEX"
    EDITED=true
    echo "- Added placeholder comment to main.tex" >> "$REPORT"
  else
    echo "- main.tex already had placeholder comment at top; no edit applied" >> "$REPORT"
  fi
else
  echo "- main.tex not found in shadow tree; no edit applied" >> "$REPORT"
fi

printf '%s\n' "diff -ruN $USER_PAPER $SHADOW_PAPER > $PATCH_FILE" >> "$CMD_LOG"
set +e
diff -ruN "$USER_PAPER" "$SHADOW_PAPER" > "$PATCH_FILE"
DIFF_RC=$?
set -e
if [[ "$DIFF_RC" -ne 0 && "$DIFF_RC" -ne 1 ]]; then
  echo "diff failed with exit code $DIFF_RC" >&2
  exit "$DIFF_RC"
fi

if [[ "$EDITED" == "true" ]]; then
  EDITED_JSON='[
    {
      "path": "main.tex",
      "change_type": "edit",
      "purpose": "Insert deterministic placeholder marker for latex_writer run",
      "risk_level": "low"
    }
  ]'
  NOTES='Placeholder mode: no semantic text edits were attempted; added one comment line in main.tex.'
else
  EDITED_JSON='[]'
  NOTES='Placeholder mode: no edits applied (main.tex missing or already marked).'
fi

cat > "$MANIFEST" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "input_paper_root": "USER/paper",
  "shadow_root": "AGENTS/tasks/$TASK_ID/work/paper_shadow/paper",
  "edited_files": $EDITED_JSON,
  "build_checks": [
    {
      "name": "latexmk",
      "cmd": "latexmk -pdf main.tex",
      "status": "skipped",
      "log_path": "AGENTS/tasks/$TASK_ID/logs/latexmk.log"
    }
  ],
  "notes": "$NOTES"
}
EOF2

{
  echo "## Outputs"
  echo "- report: AGENTS/tasks/$TASK_ID/review/${SKILL}_report.md"
  echo "- patch: AGENTS/tasks/$TASK_ID/deliverable/patchset/patch.diff"
  echo "- manifest: AGENTS/tasks/$TASK_ID/deliverable/patchset/files_manifest.json"
} >> "$REPORT"

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  run_cmd git -C "$ROOT" status --porcelain
  git -C "$ROOT" status --porcelain > "$GIT_STATUS_LOG"
else
  echo "git not available or repo missing" > "$GIT_STATUS_LOG"
fi

{
  echo
  echo "## File Snapshots"
  echo "USER/paper files:"
  (cd "$ROOT" && find USER/paper -type f | sort)
  echo
  echo "shadow files:"
  (cd "$ROOT" && find "AGENTS/tasks/$TASK_ID/work/paper_shadow/paper" -type f | sort)
} >> "$STDOUT_LOG"

bash "$ROOT/AGENTS/runtime/stage_to_gate.sh" "$ROOT" "$TASK_ID" "$SKILL"

echo "$SKILL completed for task $TASK_ID"
exit 0
