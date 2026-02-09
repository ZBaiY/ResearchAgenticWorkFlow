#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="paper_profile_update"
APPROVAL_SH="$ROOT/AGENTS/runtime/approval.sh"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
REQ="$TDIR/request.md"
USER_PAPER="${PAPER_PROFILE_USER_PAPER:-$ROOT/USER/paper}"
USER_NOTES="${PAPER_PROFILE_USER_NOTES:-$ROOT/USER/notes}"
USER_REFS_FOR_SEEDS="${PAPER_PROFILE_USER_REFS_FOR_SEEDS:-$ROOT/USER/references/for_seeds}"
OUT_DIR="$TDIR/outputs/paper_profile"
REVIEW_DIR="$TDIR/review"
LOG_DIR="$TDIR/logs/$SKILL"
PROFILE_JSON="$OUT_DIR/paper_profile.json"
REPORT_MD="$REVIEW_DIR/${SKILL}_report.md"
CMD_LOG="$LOG_DIR/commands.txt"
STDOUT_LOG="$LOG_DIR/stdout.log"
STDERR_LOG="$LOG_DIR/stderr.log"
RESOLVED_JSON="$LOG_DIR/resolved_request.json"
STAGE_CONSENT_JSON="$LOG_DIR/stage_consent.json"
USER_AUDIT_JSON="$LOG_DIR/user_write_audit.json"
BUILD_SCRIPT="$ROOT/AGENTS/skills/paper_profile_update/scripts/build_profile.py"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi

source "$APPROVAL_SH"

mkdir -p "$OUT_DIR" "$REVIEW_DIR" "$LOG_DIR"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec 3>&1 4>&2
exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

log_cmd() { printf '%s\n' "$*" >> "$CMD_LOG"; }
sha256_file() {
  if [[ -f "$1" ]]; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo ""
  fi
}

WRITE_TO_USER_REQUESTED="false"
if [[ -f "$REQ" ]] && rg -qi '^\s*write_to_user\s*:\s*true\s*$' "$REQ"; then
  WRITE_TO_USER_REQUESTED="true"
fi

ALLOW_USER_WRITE="${ALLOW_USER_WRITE:-0}"
WRITE_TO_USER="false"
if [[ "$WRITE_TO_USER_REQUESTED" == "true" && "$ALLOW_USER_WRITE" == "1" ]]; then
  WRITE_TO_USER="true"
fi

DRAFT_MODE="false"
REQUEST_STATUS="missing"
if [[ -f "$REQ" ]]; then
  REQUEST_STATUS="complete"
  if rg -qi '\bTBD\b|<[^>]+>|\?\?\?|to be determined' "$REQ"; then
    DRAFT_MODE="true"
    REQUEST_STATUS="draft_placeholders_detected"
  fi
fi

if [[ ! -f "$BUILD_SCRIPT" ]]; then
  echo "Missing build script: $BUILD_SCRIPT" >&2
  exit 2
fi

log_cmd "python3 $BUILD_SCRIPT --root $ROOT --task-id $TASK_ID --user-paper $USER_PAPER --user-notes $USER_NOTES --user-refs-for-seeds $USER_REFS_FOR_SEEDS --out-json $PROFILE_JSON --out-report $REPORT_MD --resolved-json $RESOLVED_JSON"
ONLINE_ARG=""
if [[ "${ONLINE_LOOKUP:-0}" == "1" ]]; then
  ONLINE_ARG="--online"
fi
set +e
python3 "$BUILD_SCRIPT" \
  --root "$ROOT" \
  --task-id "$TASK_ID" \
  --request-path "$REQ" \
  --user-paper "$USER_PAPER" \
  --user-notes "$USER_NOTES" \
  --user-refs-for-seeds "$USER_REFS_FOR_SEEDS" \
  --out-json "$PROFILE_JSON" \
  --out-report "$REPORT_MD" \
  --resolved-json "$RESOLVED_JSON" \
  ${ONLINE_ARG:+$ONLINE_ARG}
BUILD_RC=$?
set -e

if [[ "$BUILD_RC" -ne 0 ]]; then
  rm -f "$PROFILE_JSON" "$REPORT_MD"
  ERR_MD="$REVIEW_DIR/error.md"
  python3 - <<PY
import json
from pathlib import Path

resolved_path = Path("$RESOLVED_JSON")
err_path = Path("$ERR_MD")
task_id = "$TASK_ID"
online_lookup = "true" if "${ONLINE_LOOKUP:-0}" in {"1", "true", "yes"} else "false"

obj = {}
if resolved_path.exists():
    try:
        obj = json.loads(resolved_path.read_text(encoding="utf-8"))
    except Exception:
        obj = {}

req = obj.get("requirements", {}) if isinstance(obj, dict) else {}
missing = req.get("missing", []) if isinstance(req, dict) else []
if not isinstance(missing, list):
    missing = []
error_code = "PROFILE_REQUIREMENTS_NOT_MET" if missing else "PAPER_PROFILE_BUILD_FAILED"
inputs = obj.get("inputs_scanned", {}) if isinstance(obj, dict) else {}
next_actions = obj.get("next_actions", []) if isinstance(obj, dict) else []
if not isinstance(next_actions, list):
    next_actions = []
stop_reason = obj.get("stop_reason", "Stopped early to avoid low-quality partial output.")

lines = [
    "# Error Report",
    "",
    f"error_code: {error_code}",
    f"missing: {json.dumps(missing)}" if missing else "missing: []",
    "completeness_rules: seed counts only if abstract present and required fields are complete",
    f"online_lookup: {str(obj.get('online_lookup', online_lookup)).lower()}",
    f"inputs_scanned: {json.dumps(inputs)}",
    "next_actions:",
]
for x in next_actions:
    lines.append(f"- {x}")
if not next_actions:
    lines.extend([
        "- add USER/references/for_seeds files or USER/paper/*.bib with abstracts",
        "- set online_lookup=true in request or run with --online",
        "- specify/verify USER/paper/main.tex and include graph",
    ])
lines += [
    f"stop_reason: {stop_reason}",
]
err_path.parent.mkdir(parents=True, exist_ok=True)
err_path.write_text("\\n".join(lines) + "\\n", encoding="utf-8")
PY
  {
    if [[ -f "$ERR_MD" ]] && rg -q '^error_code: PROFILE_REQUIREMENTS_NOT_MET$' "$ERR_MD"; then
      echo "ERROR_CODE=PROFILE_REQUIREMENTS_NOT_MET"
    else
      echo "ERROR_CODE=PAPER_PROFILE_BUILD_FAILED"
    fi
    if [[ -f "$ERR_MD" ]]; then
      sed -n '/^error_code:/p;/^missing:/p;/^completeness_rules:/p;/^online_lookup:/p;/^inputs_scanned:/p;/^next_actions:/,/^stop_reason:/p' "$ERR_MD"
    fi
    echo "SEE=AGENTS/tasks/$TASK_ID/review/error.md"
  } >&4
  exit 2
fi

export WRITE_TO_USER_REQUESTED ALLOW_USER_WRITE WRITE_TO_USER REQUEST_STATUS DRAFT_MODE
python3 - <<PY
import json
import os
from pathlib import Path
p = Path("$RESOLVED_JSON")
obj = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
obj.update({
  "write_to_user_requested": os.environ.get("WRITE_TO_USER_REQUESTED", "false").lower() == "true",
  "allow_user_write": os.environ.get("ALLOW_USER_WRITE", "0"),
  "write_to_user": os.environ.get("WRITE_TO_USER", "false").lower() == "true",
  "request_status": os.environ.get("REQUEST_STATUS", ""),
  "draft_mode": os.environ.get("DRAFT_MODE", "false").lower() == "true",
})
p.write_text(json.dumps(obj, indent=2), encoding="utf-8")
PY

maybe_stage() {
  local resp_lc="n"
  if approval_stage_confirm "Stage profile update package to GATE/staged/$TASK_ID? (y/N) "; then
    resp_lc="y"
  fi
  if [[ "$resp_lc" != "y" ]]; then
    cat > "$STAGE_CONSENT_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "staged": false,
  "user_response": "$resp_lc",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF2
    return 0
  fi

  STAGED_SKILL_DIR="$ROOT/GATE/staged/$TASK_ID/$SKILL"
  mkdir -p "$STAGED_SKILL_DIR"
  cp "$PROFILE_JSON" "$STAGED_SKILL_DIR/paper_profile.json"
  cp "$REPORT_MD" "$STAGED_SKILL_DIR/paper_profile_update_report.md"

  cat > "$STAGED_SKILL_DIR/STAGE.md" <<EOF2
# Staged Profile Update

- task_id: $TASK_ID
- skill: $SKILL
- staged_dir: GATE/staged/$TASK_ID/$SKILL

## Staged files
- paper_profile.json
- paper_profile_update_report.md

## Manual promotion to USER (canonical)
cp GATE/staged/$TASK_ID/$SKILL/paper_profile.json USER/paper/meta/paper_profile.json

## Minimal acceptance checklist
- Confirm keywords/categories reflect manuscript intent.
- Confirm short blurb and themes are accurate.
- Promote to USER only after manual review.
EOF2

  cat > "$STAGE_CONSENT_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "staged": true,
  "user_response": "$resp_lc",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "staged_dir": "GATE/staged/$TASK_ID/$SKILL"
}
EOF2
}

if [[ "$WRITE_TO_USER" == "true" ]]; then
  warn="WARNING: This will write into USER/ (canonical workspace). This bypasses the normal GATE staging.\nProceed? Type WRITE USER to confirm (anything else cancels): "
  confirm="$(approval_text "$warn" "AUTO-NO")"

  if [[ "$confirm" == "WRITE USER" ]]; then
    USER_META_DIR="$ROOT/USER/paper/meta"
    USER_META_FILE="$USER_META_DIR/paper_profile.json"
    mkdir -p "$USER_META_DIR"
    cp "$PROFILE_JSON" "$USER_META_FILE"
    cat > "$USER_AUDIT_JSON" <<EOF2
{
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "files_written": ["USER/paper/meta/paper_profile.json"],
  "sha256": "$(sha256_file "$USER_META_FILE")",
  "user_confirmation_text": "$(printf '%s' "$confirm")"
}
EOF2

    cat > "$STAGE_CONSENT_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "staged": false,
  "user_response": "direct_user_write",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "notes": "write_to_user confirmed with exact phrase"
}
EOF2
  else
    maybe_stage
  fi
else
  maybe_stage
fi

echo "$SKILL completed for task $TASK_ID"
