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
USER_PAPER="$ROOT/USER/paper"
USER_NOTES="$ROOT/USER/notes"
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

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi

source "$APPROVAL_SH"

mkdir -p "$OUT_DIR" "$REVIEW_DIR" "$LOG_DIR"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

log_cmd() { printf '%s\n' "$*" >> "$CMD_LOG"; }
sha256_file() {
  if [[ -f "$1" ]]; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo ""
  fi
}

WRITE_TO_USER="false"
if [[ -f "$REQ" ]] && rg -qi '^\s*write_to_user\s*:\s*true\s*$' "$REQ"; then
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

# Collect source files (read-only inputs).
SRC_FILES=()
while IFS= read -r f; do
  SRC_FILES+=("$f")
done < <(
  {
    find "$USER_PAPER" -maxdepth 1 -type f -name '*.tex' 2>/dev/null || true
    find "$USER_NOTES" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true
  } | sort
)

# Build a deterministic profile payload.
SRC_COUNT="${#SRC_FILES[@]}"
if [[ "$SRC_COUNT" -eq 0 ]]; then
  KEYWORDS='["TBD", "placeholder"]'
  CATEGORIES='["unclassified"]'
  BLURB='"No USER/paper/*.tex or USER/notes/*.md were found; generated placeholder profile."'
  THEMES='["profile_bootstrap"]'
  NOTES='"placeholder profile generated due to missing source files"'
else
  # simple deterministic extraction by frequency of words in source text
  TMP_WORDS="$LOG_DIR/words.tmp"
  : > "$TMP_WORDS"
  for f in "${SRC_FILES[@]}"; do
    tr -cs '[:alnum:]' '\n' < "$f" | tr '[:upper:]' '[:lower:]' >> "$TMP_WORDS"
  done
  TOP_WORDS=()
  while IFS= read -r w; do
    TOP_WORDS+=("$w")
  done < <(awk 'length($1)>=5{c[$1]++} END{for(k in c) print c[k],k}' "$TMP_WORDS" | sort -nr | awk 'NR<=6{print $2}')
  rm -f "$TMP_WORDS"

  if [[ "${#TOP_WORDS[@]}" -eq 0 ]]; then
    TOP_WORDS=("manuscript" "analysis" "results")
  fi

  KEYWORDS='['
  for i in "${!TOP_WORDS[@]}"; do
    [[ "$i" -gt 0 ]] && KEYWORDS+=', '
    KEYWORDS+="\"${TOP_WORDS[$i]}\""
  done
  KEYWORDS+=']'

  CATEGORIES='["physics", "manuscript"]'
  BLURB='"Profile generated from local manuscript/notes content; review and refine before promotion."'
  THEMES='["core_claims", "method_summary", "related_work_positioning"]'
  NOTES='"auto-generated profile from local USER paper/notes inputs"'
fi

SRC_JSON='['
for i in "${!SRC_FILES[@]}"; do
  rel="${SRC_FILES[$i]#$ROOT/}"
  [[ "$i" -gt 0 ]] && SRC_JSON+=', '
  SRC_JSON+="\"$rel\""
done
SRC_JSON+=']'

cat > "$PROFILE_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "generated_at_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "source_files": $SRC_JSON,
  "profile": {
    "keywords": $KEYWORDS,
    "categories": $CATEGORIES,
    "short_blurb": $BLURB,
    "related_work_themes": $THEMES
  },
  "notes": $NOTES
}
EOF2

cat > "$REPORT_MD" <<EOF2
# paper_profile_update Report

- task_id: $TASK_ID
- skill: $SKILL
- source_files_count: $SRC_COUNT
- request_status: $REQUEST_STATUS
- draft_mode: $DRAFT_MODE
- output_profile: AGENTS/tasks/$TASK_ID/outputs/paper_profile/paper_profile.json

## Summary
- Built a paper profile payload from available USER manuscript/notes sources.
- If request placeholders are present (for example, TBD), run proceeds in draft mode using canonical sources.
- This profile is a candidate and should be reviewed before promotion.

## Fields
- keywords
- categories
- short_blurb
- related_work_themes

## Inputs used
$SRC_JSON

## Promotion target
- Canonical user file (manual by default): USER/paper/meta/paper_profile.json
EOF2

cat > "$RESOLVED_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "write_to_user": $WRITE_TO_USER,
  "source_files_count": $SRC_COUNT,
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF2

maybe_stage() {
  local resp_lc="n"
  if approval_confirm "Stage profile update package to GATE/staged/$TASK_ID? (y/N) "; then
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
