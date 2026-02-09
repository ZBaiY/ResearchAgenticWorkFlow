#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="${3:-}"
APPROVAL_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/approval.sh"

if [[ -z "$ROOT" || -z "$TASK_ID" || -z "$SKILL" ]]; then
  echo "Usage: stage_to_gate.sh <repo_root> <task_id> <skill_name>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
GATE_BASE="$ROOT/GATE/staged"
TASK_STAGE_DIR="$GATE_BASE/$TASK_ID"
SKILL_STAGE_DIR="$TASK_STAGE_DIR/$SKILL"
STAGE_MD="$TASK_STAGE_DIR/STAGE.md"
LOG_SKILL_DIR="$TDIR/logs/$SKILL"
CONSENT_JSON="$LOG_SKILL_DIR/stage_consent.json"

source "$APPROVAL_SH"

mkdir -p "$LOG_SKILL_DIR"

if [[ ! -d "$TDIR" ]]; then
  cat > "$CONSENT_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "staged": false,
  "user_response": "",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "notes": "task directory missing"
}
EOF2
  exit 0
fi

# Candidate artifacts (minimal reviewable/promotable set).
declare -a SRC=()
declare -a DST=()

add_file() {
  local s="$1" d="$2"
  [[ -f "$s" ]] || return 0
  SRC+=("$s")
  DST+=("$d")
}

add_dir() {
  local s="$1" d="$2"
  [[ -d "$s" ]] || return 0
  SRC+=("$s")
  DST+=("$d")
}

add_file "$TDIR/deliverable/patchset/patch.diff" "patches/patch.diff"
add_file "$TDIR/deliverable/patchset/files_manifest.json" "patches/files_manifest.json"

if [[ -d "$TDIR/review" ]]; then
  while IFS= read -r f; do
    rel="review/$(basename "$f")"
    add_file "$f" "$rel"
  done < <(find "$TDIR/review" -maxdepth 1 -type f \( -name '*.md' -o -name '*.bib' \) | sort)
fi

add_dir "$TDIR/deliverable/src" "deliverable/src"
add_dir "$TDIR/deliverable/pptx" "deliverable/pptx"
add_dir "$TDIR/deliverable/prd" "deliverable/prd"
add_file "$TDIR/outputs/compute/result.json" "outputs/compute/result.json"
add_file "$TDIR/outputs/paper_profile/paper_profile.json" "paper_profile.json"
add_file "$TDIR/logs/compute/consent.json" "logs/compute_consent.json"

if [[ ${#SRC[@]} -eq 0 ]]; then
  cat > "$CONSENT_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "staged": false,
  "user_response": "",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "notes": "no candidate artifacts to stage"
}
EOF2
  exit 0
fi

RESP_LC="n"
if approval_stage_confirm "Stage candidate deliverables to GATE/staged/$TASK_ID? (y/N) "; then
  RESP_LC="y"
fi

if [[ "$RESP_LC" != "y" ]]; then
  cat > "$CONSENT_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "staged": false,
  "user_response": "$RESP_LC",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "notes": "user declined staging"
}
EOF2
  exit 0
fi

mkdir -p "$SKILL_STAGE_DIR"
rm -rf "$SKILL_STAGE_DIR"/*

STAGED_LIST=""
for i in "${!SRC[@]}"; do
  s="${SRC[$i]}"
  d="${DST[$i]}"
  out="$SKILL_STAGE_DIR/$d"
  mkdir -p "$(dirname "$out")"
  if [[ -d "$s" ]]; then
    cp -R "$s" "$out"
  else
    cp "$s" "$out"
  fi
  STAGED_LIST+="- $SKILL/$d\n"
done

mkdir -p "$TASK_STAGE_DIR"
cat > "$STAGE_MD" <<EOF2
# Staged Deliverables

- task_id: $TASK_ID
- skill: $SKILL
- staged_at_utc: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- staged_dir: GATE/staged/$TASK_ID/$SKILL

## What was staged
$(printf '%b' "$STAGED_LIST")

## Manual Promotion Commands (USER is manual-only)
- Patch-based update (if present):
  \
  git apply GATE/staged/$TASK_ID/$SKILL/patches/patch.diff
- Compute source export (if present):
  \
  cp -r GATE/staged/$TASK_ID/$SKILL/deliverable/src USER/src/compute/$TASK_ID/
- Slide export (if present):
  \
  cp -r GATE/staged/$TASK_ID/$SKILL/deliverable/slides USER/presentations/$TASK_ID/
- Literature refs (if present):
  \
  cp GATE/staged/$TASK_ID/$SKILL/review/refs.bib USER/paper/bib/$TASK_ID.refs.bib

## Minimal Acceptance Checklist
- Confirm report summary matches request intent.
- Inspect patch/source/result summary before promoting.
- Promote only approved files into USER manually.
EOF2

# Machine-readable promotion contract (authoritative).
if [[ "$SKILL" == "paper_profile_update" && -f "$SKILL_STAGE_DIR/paper_profile.json" ]]; then
  cat > "$TASK_STAGE_DIR/PROMOTE.json" <<EOF2
{
  "kind": "promotion_contract",
  "skill": "paper_profile_update",
  "from": "GATE/staged/$TASK_ID/paper_profile_update",
  "to": "USER/paper/meta/paper_profile.json",
  "mappings": [
    {
      "src": "GATE/staged/$TASK_ID/paper_profile_update/paper_profile.json",
      "dst": "USER/paper/meta/paper_profile.json"
    }
  ],
  "command": ["bash", "AGENTS/runtime/promote_to_user.sh", "--task", "$TASK_ID"],
  "confirmation_required": true,
  "allowed_responses": ["yes", "y", "no", "n"],
  "on_yes": "execute",
  "on_no": "noop"
}
EOF2
fi

cat > "$CONSENT_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "staged": true,
  "user_response": "$RESP_LC",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "staged_dir": "GATE/staged/$TASK_ID/$SKILL",
  "stage_md": "GATE/staged/$TASK_ID/STAGE.md"
}
EOF2

exit 0
