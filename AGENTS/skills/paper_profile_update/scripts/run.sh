#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="paper_profile_update"

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
BUILD_SCRIPT="$ROOT/AGENTS/skills/paper_profile_update/scripts/build_profile.py"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi

# paper_profile_update must run non-interactively end-to-end.
if [[ "${APPROVAL_MODE:-interactive}" == "interactive" ]]; then
  export APPROVAL_MODE="no"
fi

has_tex() {
  local d="$1"
  [[ -d "$d" ]] || return 1
  find "$d" -type f -name '*.tex' -print -quit 2>/dev/null | grep -q .
}

has_paper_inputs() {
  local d="$1"
  [[ -d "$d" ]] || return 1
  find "$d" -type f \( -name '*.tex' -o -name '*.bib' -o -name '*.md' -o -name '*.txt' -o -name '*.pdf' \) -print -quit 2>/dev/null | grep -q .
}

# Fallback input roots for repos that keep files outside USER/.
# Never fall back to repo root: that pollutes discovery with AGENTS/runtime files.
if ! has_paper_inputs "$USER_PAPER"; then
  if has_tex "$ROOT/paper"; then
    USER_PAPER="$ROOT/paper"
  fi
fi

if [[ ! -d "$USER_NOTES" && -d "$ROOT/notes" ]]; then
  USER_NOTES="$ROOT/notes"
fi

if [[ ! -d "$USER_REFS_FOR_SEEDS" ]]; then
  if [[ -d "$ROOT/references/for_seeds" ]]; then
    USER_REFS_FOR_SEEDS="$ROOT/references/for_seeds"
  elif [[ -d "$ROOT/references" ]]; then
    USER_REFS_FOR_SEEDS="$ROOT/references"
  fi
fi

mkdir -p "$OUT_DIR" "$REVIEW_DIR" "$LOG_DIR"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec 3>&1 4>&2
exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

log_cmd() { printf '%s\n' "$*" >> "$CMD_LOG"; }

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

req_bool() {
  local key="$1"
  local default="${2:-}"
  [[ -f "$REQ" ]] || { [[ -n "$default" ]] && echo "$default"; return 0; }
  local v
  v="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*(true|false|yes|no|1|0)[[:space:]]*$/\\1/ip" "$REQ" | head -n1 | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$v" ]]; then
    case "$v" in
      true|yes|1) echo "1" ;;
      false|no|0) echo "0" ;;
      *) [[ -n "$default" ]] && echo "$default" ;;
    esac
    return 0
  fi
  [[ -n "$default" ]] && echo "$default"
}

req_int() {
  local key="$1"
  local default="${2:-3}"
  [[ -f "$REQ" ]] || { echo "$default"; return 0; }
  local v
  v="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*$/\\1/p" "$REQ" | head -n1)"
  if [[ -n "$v" ]]; then
    echo "$v"
  else
    echo "$default"
  fi
}

if [[ ! -f "$BUILD_SCRIPT" ]]; then
  echo "Missing build script: $BUILD_SCRIPT" >&2
  exit 2
fi

log_cmd "python3 $BUILD_SCRIPT --root $ROOT --task-id $TASK_ID --user-paper $USER_PAPER --user-notes $USER_NOTES --user-refs-for-seeds $USER_REFS_FOR_SEEDS --out-json $PROFILE_JSON --out-report $REPORT_MD --resolved-json $RESOLVED_JSON"
ONLINE_ARG=""
REQUEST_ONLINE_LOOKUP="$(req_bool online_lookup "${ONLINE_LOOKUP:-0}")"
REQUEST_ONLINE_FAILFAST="$(req_bool online_failfast "${ONLINE_FAILFAST:-1}")"
REQUEST_MIN_COMPLETE_SEEDS="$(req_int min_complete_seeds "${PAPER_PROFILE_MIN_COMPLETE_SEEDS:-3}")"
export ONLINE_LOOKUP="$REQUEST_ONLINE_LOOKUP"
export ONLINE_FAILFAST="$REQUEST_ONLINE_FAILFAST"
export PAPER_PROFILE_MIN_COMPLETE_SEEDS="$REQUEST_MIN_COMPLETE_SEEDS"
if [[ "$REQUEST_ONLINE_LOOKUP" == "1" ]]; then
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
  BUILD_ERR_TAIL="$(tail -n 20 "$STDERR_LOG" 2>/dev/null | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' || true)"
  python3 - <<PY
import json
from pathlib import Path

resolved_path = Path("$RESOLVED_JSON")
err_path = Path("$ERR_MD")
task_id = "$TASK_ID"
online_requested = "true" if "${ONLINE_LOOKUP:-0}" in {"1", "true", "yes"} else "false"
net_allowed = "true" if "${NET_ALLOWED:-0}" in {"1", "true", "yes"} else "false"
online_failfast = "true" if "${ONLINE_FAILFAST:-1}" in {"1", "true", "yes"} else "false"
min_complete_seeds = int("${PAPER_PROFILE_MIN_COMPLETE_SEEDS:-3}" or "3")

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
error_code = "PAPER_PROFILE_BUILD_FAILED"
inputs = obj.get("inputs_scanned", {}) if isinstance(obj, dict) else {}
stages = obj.get("stage_breakdown", []) if isinstance(obj, dict) else []
next_actions = obj.get("next_actions", []) if isinstance(obj, dict) else []
if not isinstance(next_actions, list):
    next_actions = []
stop_reason = obj.get("stop_reason", "Stopped early to avoid low-quality partial output.")
build_error_tail = """$BUILD_ERR_TAIL""".strip()

lines = [
    "# Error Report",
    "",
    f"error_code: {error_code}",
    f"cause: {build_error_tail}" if build_error_tail else "cause: unknown",
    f"missing: {json.dumps(missing)}" if missing else "missing: []",
    "completeness_rules: COMPLETE means title + (authors or link/arxiv_id/doi); abstract is optional",
    f"online_requested: {str(obj.get('online_requested', online_requested)).lower()}",
    f"net_allowed: {str(obj.get('net_allowed', net_allowed)).lower()}",
    f"online_attempted: {str(obj.get('online_attempted', False)).lower()}",
    f"online_backend_used: {obj.get('online_backend_used', 'none')}",
    f"online_fail_reason: {obj.get('online_fail_reason', None)}",
    f"validation_phase: {obj.get('validation_phase', 'post_online')}",
    f"online_failfast: {str(obj.get('online_failfast', online_failfast)).lower()}",
    f"min_complete_seeds: {obj.get('min_complete_seeds', min_complete_seeds)}",
    f"inputs_scanned: {json.dumps(inputs)}",
    "stages_attempted:",
]
if isinstance(stages, list):
    for st in stages:
        if not isinstance(st, dict):
            continue
        lines.append(
            "- "
            + f"{st.get('stage','unknown')}: attempted={st.get('attempted')} "
            + f"added={st.get('added',0)} complete={st.get('complete_count',0)} "
            + f"partial={st.get('partial_count',0)} "
            + f"missing={st.get('top_missing_fields',[])}"
        )
lines.append("next_actions:")
for x in next_actions:
    lines.append(f"- {x}")
if not next_actions:
    lines.extend([
        "- Add 3 papers into USER/references/for_seeds/",
        "- Add a .bib under USER/paper/",
        "- Enable online_lookup=true",
    ])
lines += [
    f"stop_reason: {stop_reason}",
]
err_path.parent.mkdir(parents=True, exist_ok=True)
err_path.write_text("\\n".join(lines) + "\\n", encoding="utf-8")
PY
  {
    echo "ERROR_CODE=PAPER_PROFILE_BUILD_FAILED"
    if [[ -f "$ERR_MD" ]]; then
      MISSING_LINE="$(sed -n 's/^missing: //p' "$ERR_MD" | head -n1)"
      [[ -n "$MISSING_LINE" ]] && echo "MISSING=$MISSING_LINE"
      ACTION_LINE="$(sed -n 's/^- //p' "$ERR_MD" | head -n1)"
      [[ -n "$ACTION_LINE" ]] && echo "ACTION=$ACTION_LINE"
    elif [[ -n "$BUILD_ERR_TAIL" ]]; then
      echo "ACTION=Check review/error.md and add required inputs."
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

echo "$SKILL completed for task $TASK_ID"
