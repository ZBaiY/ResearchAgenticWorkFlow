#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="paper_profile_update"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: checks.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
PROFILE_JSON="$TDIR/outputs/paper_profile/paper_profile.json"
REPORT_MD="$TDIR/review/paper_profile_update_report.md"
LOG_DIR="$TDIR/logs/$SKILL"

[[ -d "$TDIR" ]] || { echo "Task folder missing: $TDIR" >&2; exit 2; }
[[ -f "$PROFILE_JSON" ]] || { echo "Missing profile json" >&2; exit 1; }
[[ -f "$REPORT_MD" ]] || { echo "Missing report" >&2; exit 1; }
[[ -f "$LOG_DIR/resolved_request.json" ]] || { echo "Missing resolved_request.json" >&2; exit 1; }
[[ -f "$LOG_DIR/stage_consent.json" ]] || { echo "Missing stage_consent.json" >&2; exit 1; }

if command -v python3 >/dev/null 2>&1; then
  python3 - <<PY
import json
p = json.load(open("$PROFILE_JSON"))
req = ["keywords", "categories", "short_blurb", "related_work_themes"]
for k in req:
    assert k in p["profile"], k
print("PROFILE_SCHEMA=ok")
PY
fi

if command -v git >/dev/null 2>&1; then
  BAD="$(git -C "$ROOT" status --porcelain USER GATE | rg -v '^\?\? GATE/staged/' || true)"
  if [[ -n "$BAD" ]]; then
    echo "ERROR: unexpected USER/GATE modifications:" >&2
    echo "$BAD" >&2
    exit 1
  fi
fi

echo "CHECKS=ok TASK=$TASK_ID"
