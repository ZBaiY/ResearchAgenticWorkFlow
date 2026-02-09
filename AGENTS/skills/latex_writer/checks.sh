#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="latex_writer"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: checks.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
SHADOW_PAPER="$TDIR/work/paper_shadow/paper"
LOG_DIR="$TDIR/logs"
REPORT="$TDIR/review/${SKILL}_report.md"
PATCH_FILE="$TDIR/deliverable/patchset/patch.diff"
LATEXMK_LOG="$LOG_DIR/latexmk.log"

mkdir -p "$LOG_DIR"

USER_GATE_STATUS="skipped"
PATCH_STATUS="fail"
LATEXMK_STATUS="skipped"

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$ROOT" status --porcelain | rg -q '^(.. )?(USER/|GATE/)'; then
    USER_GATE_STATUS="fail"
  else
    USER_GATE_STATUS="ok"
  fi
fi

if [[ -f "$PATCH_FILE" ]]; then
  PATCH_STATUS="ok"
fi

if command -v latexmk >/dev/null 2>&1; then
  if [[ -d "$SHADOW_PAPER" ]]; then
    set +e
    (cd "$SHADOW_PAPER" && latexmk -pdf main.tex) > "$LATEXMK_LOG" 2>&1
    RC=$?
    set -e
    if [[ "$RC" -eq 0 ]]; then
      LATEXMK_STATUS="ok"
    else
      LATEXMK_STATUS="fail"
    fi
  fi
else
  echo "latexmk not found; skipped" > "$LATEXMK_LOG"
fi

{
  echo
  echo "## checks.sh"
  echo "- USER/GATE unchanged check: $USER_GATE_STATUS"
  echo "- patch.diff exists: $PATCH_STATUS"
  echo "- latexmk in shadow: $LATEXMK_STATUS"
} >> "$REPORT"

echo "USER_GATE_STATUS=$USER_GATE_STATUS"
echo "PATCH_STATUS=$PATCH_STATUS"
echo "LATEXMK_STATUS=$LATEXMK_STATUS"

if [[ "$USER_GATE_STATUS" == "fail" ]]; then
  exit 1
fi
if [[ "$PATCH_STATUS" == "fail" ]]; then
  exit 1
fi

exit 0
