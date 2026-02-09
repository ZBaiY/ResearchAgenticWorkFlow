#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="prd_writer"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
REQUEST_FILE="$TDIR/request.md"
WORK_DIR="$TDIR/work"
CONTEXT_FILE="$WORK_DIR/context.md"
CONTEXT_DIR="$WORK_DIR/context"
DELIV_DIR="$TDIR/deliverable/prd"
REVIEW_DIR="$TDIR/review"
LOG_DIR="$TDIR/logs"
PRD_MD="$DELIV_DIR/PRD.md"
PRD_JSON="$DELIV_DIR/PRD.json"
MANIFEST="$DELIV_DIR/files_manifest.json"
REPORT="$REVIEW_DIR/${SKILL}_report.md"
CMD_LOG="$LOG_DIR/commands.txt"
STDOUT_LOG="$LOG_DIR/${SKILL}.stdout.log"
STDERR_LOG="$LOG_DIR/${SKILL}.stderr.log"
GIT_STATUS_LOG="$LOG_DIR/git_status.txt"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi
if [[ ! -f "$REQUEST_FILE" ]]; then
  echo "Missing required input file: $REQUEST_FILE" >&2
  exit 2
fi

mkdir -p "$DELIV_DIR" "$REVIEW_DIR" "$LOG_DIR"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

run_cmd() {
  printf '%s\n' "$*" >> "$CMD_LOG"
  "$@"
}

json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

printf '%s\n' "cat $REQUEST_FILE" >> "$CMD_LOG"
INPUTS=("AGENTS/tasks/$TASK_ID/request.md")
CONTEXTS=()

if [[ -f "$CONTEXT_FILE" ]]; then
  INPUTS+=("AGENTS/tasks/$TASK_ID/work/context.md")
  CONTEXTS+=("$CONTEXT_FILE")
fi
if [[ -d "$CONTEXT_DIR" ]]; then
  while IFS= read -r f; do
    INPUTS+=("${f#$ROOT/}")
    CONTEXTS+=("$f")
  done < <(find "$CONTEXT_DIR" -type f -name '*.md' | sort)
fi

raw_title="$(sed -nE 's/^#\s+(.+)$/\1/p' "$REQUEST_FILE" | head -n 1)"
if [[ -z "$raw_title" || "$raw_title" == "request.md" ]]; then
  TITLE="Task $TASK_ID"
else
  TITLE="$raw_title"
fi

DATE_STR="TBD"
OWNER="TBD"
VERSION="0.1"
STATUS="draft"
LINKS="TBD"

GOAL1="TBD: Define the primary user outcome for this work."
GOAL2="TBD: Define measurable success criteria for the first release."
GOAL3="TBD: Define delivery scope for this task."

NON_GOAL1="TBD: Explicitly out of scope items."
NON_GOAL2="TBD: Features deferred to future phases."

FR1="TBD: System must provide the core capability described in request.md."
NFR1="TBD: Solution must meet reliability/security/performance expectations defined by stakeholders."

AC1="The deliverable demonstrates FR-001 with a reproducible verification step."
AC2="The deliverable satisfies NFR-001 based on agreed validation checks."

RISK1="TBD: Requirement ambiguity could expand scope."
RISK2="TBD: Missing stakeholder decisions could delay execution."

OPEN_Q=(
  "Who is the owner for this PRD and final sign-off?"
  "What is the target release date or milestone date?"
  "Which links/specs should be listed as normative references?"
)

if [[ ${#CONTEXTS[@]} -eq 0 ]]; then
  OPEN_Q+=("What additional context files should be added under AGENTS/tasks/$TASK_ID/work/context/ ?")
fi

APPENDIX_REQUEST="$(sed -n '1,80p' "$REQUEST_FILE")"

cat > "$PRD_MD" <<EOF2
# PRD: $TITLE

## 0. Metadata
- Owner: $OWNER
- Date: $DATE_STR
- Version: $VERSION
- Status: $STATUS
- Related task_id: $TASK_ID
- Links: $LINKS

## 1. Problem statement
TBD: Define what problem is being solved, for which users, and why now.

## 2. Goals
- $GOAL1
- $GOAL2
- $GOAL3

## 3. Non-goals
- $NON_GOAL1
- $NON_GOAL2

## 4. Users & use cases
- Persona: TBD
- Primary workflow: TBD
- Secondary workflow: TBD

## 5. Requirements
- Functional requirements
- FR-001: $FR1

- Non-functional requirements (performance, reliability, security, privacy)
- NFR-001: $NFR1

## 6. Interfaces & integration
- APIs/CLI: TBD
- File I/O: input from
$(printf -- '- %s\n' "${INPUTS[@]}")
- Dependencies: TBD
- Data contracts: TBD

## 7. Success metrics
- TBD: Metric 1 with threshold.
- TBD: Metric 2 with threshold.

## 8. Acceptance criteria
- AC-001 [FR-001]: $AC1
- AC-002 [NFR-001]: $AC2

## 9. Risks & mitigations
- Risk: $RISK1
  Mitigation: TBD
- Risk: $RISK2
  Mitigation: TBD

## 10. Open questions
$(for q in "${OPEN_Q[@]}"; do printf -- '- %s\n' "$q"; done)

## 11. Milestones
- M1: TBD (owner: TBD, date: TBD)
- M2: TBD (owner: TBD, date: TBD)
- M3: TBD (owner: TBD, date: TBD)

## 12. Appendix
- Raw request excerpt:

\`\`\`markdown
$APPENDIX_REQUEST
\`\`\`
EOF2

cat > "$PRD_JSON" <<EOF2
{
  "title": "$(json_escape "$TITLE")",
  "metadata": {
    "owner": "$(json_escape "$OWNER")",
    "date": "$(json_escape "$DATE_STR")",
    "version": "$(json_escape "$VERSION")",
    "status": "$(json_escape "$STATUS")",
    "related_task_id": "$(json_escape "$TASK_ID")",
    "links": []
  },
  "goals": [
    "$(json_escape "$GOAL1")",
    "$(json_escape "$GOAL2")",
    "$(json_escape "$GOAL3")"
  ],
  "non_goals": [
    "$(json_escape "$NON_GOAL1")",
    "$(json_escape "$NON_GOAL2")"
  ],
  "requirements": [
    {"id": "FR-001", "type": "functional", "text": "$(json_escape "$FR1")"},
    {"id": "NFR-001", "type": "non_functional", "text": "$(json_escape "$NFR1")"}
  ],
  "acceptance_criteria": [
    {"id": "AC-001", "maps_to": ["FR-001"], "text": "$(json_escape "$AC1")"},
    {"id": "AC-002", "maps_to": ["NFR-001"], "text": "$(json_escape "$AC2")"}
  ],
  "risks": [
    "$(json_escape "$RISK1")",
    "$(json_escape "$RISK2")"
  ],
  "open_questions": [
$(for i in "${!OPEN_Q[@]}"; do
  if [[ "$i" -lt $((${#OPEN_Q[@]} - 1)) ]]; then
    printf '    "%s",\n' "$(json_escape "${OPEN_Q[$i]}")"
  else
    printf '    "%s"\n' "$(json_escape "${OPEN_Q[$i]}")"
  fi
done)
  ]
}
EOF2

SECTIONS=(
  "0. Metadata"
  "1. Problem statement"
  "2. Goals"
  "3. Non-goals"
  "4. Users & use cases"
  "5. Requirements"
  "6. Interfaces & integration"
  "7. Success metrics"
  "8. Acceptance criteria"
  "9. Risks & mitigations"
  "10. Open questions"
  "11. Milestones"
  "12. Appendix"
)

TBD_COUNT="$(rg -o 'TBD' "$PRD_MD" | wc -l | tr -d ' ')"
FR_COUNT="$(sed -nE 's/^[[:space:]]*-[[:space:]]*(FR-[0-9]{3}):.*/\1/p' "$PRD_MD" | wc -l | tr -d ' ')"
NFR_COUNT="$(sed -nE 's/^[[:space:]]*-[[:space:]]*(NFR-[0-9]{3}):.*/\1/p' "$PRD_MD" | wc -l | tr -d ' ')"
OPEN_COUNT="${#OPEN_Q[@]}"

{
  echo "# prd_writer Report"
  echo
  echo "- task_id: $TASK_ID"
  echo "- skill: $SKILL"
  echo
  echo "## Inputs used"
  for in_file in "${INPUTS[@]}"; do
    echo "- $in_file"
  done
  echo
  echo "## Section quality summary"
  echo "- Sections with TBD content: all sections should be reviewed; detected TBD token count = $TBD_COUNT"
  echo "- Weak sections likely requiring user input: Metadata, Problem statement, Users & use cases, Success metrics, Milestones"
  echo
  echo "## Requirement mapping gaps"
  echo "- Functional requirements count: $FR_COUNT"
  echo "- Non-functional requirements count: $NFR_COUNT"
  echo "- Acceptance criteria currently map to FR-001 and NFR-001 only; expand mappings as requirements grow."
} > "$REPORT"

OUTPUTS=(
  "AGENTS/tasks/$TASK_ID/deliverable/prd/PRD.md"
  "AGENTS/tasks/$TASK_ID/deliverable/prd/PRD.json"
  "AGENTS/tasks/$TASK_ID/review/prd_writer_report.md"
  "AGENTS/tasks/$TASK_ID/deliverable/prd/files_manifest.json"
  "AGENTS/tasks/$TASK_ID/logs/commands.txt"
  "AGENTS/tasks/$TASK_ID/logs/prd_writer.stdout.log"
  "AGENTS/tasks/$TASK_ID/logs/prd_writer.stderr.log"
  "AGENTS/tasks/$TASK_ID/logs/git_status.txt"
)

cat > "$MANIFEST" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "inputs": [
$(for i in "${!INPUTS[@]}"; do
  if [[ "$i" -lt $((${#INPUTS[@]} - 1)) ]]; then
    printf '    "%s",\n' "${INPUTS[$i]}"
  else
    printf '    "%s"\n' "${INPUTS[$i]}"
  fi
done)
  ],
  "outputs": [
$(for i in "${!OUTPUTS[@]}"; do
  if [[ "$i" -lt $((${#OUTPUTS[@]} - 1)) ]]; then
    printf '    "%s",\n' "${OUTPUTS[$i]}"
  else
    printf '    "%s"\n' "${OUTPUTS[$i]}"
  fi
done)
  ],
  "sections_present": [
$(for i in "${!SECTIONS[@]}"; do
  if [[ "$i" -lt $((${#SECTIONS[@]} - 1)) ]]; then
    printf '    "%s",\n' "${SECTIONS[$i]}"
  else
    printf '    "%s"\n' "${SECTIONS[$i]}"
  fi
done)
  ],
  "requirement_counts": {
    "functional": $FR_COUNT,
    "non_functional": $NFR_COUNT
  },
  "open_questions_count": $OPEN_COUNT,
  "status": "$STATUS"
}
EOF2

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  run_cmd git -C "$ROOT" status --porcelain
  git -C "$ROOT" status --porcelain > "$GIT_STATUS_LOG"
else
  echo "git not available or repo missing" > "$GIT_STATUS_LOG"
fi

bash "$ROOT/AGENTS/runtime/stage_to_gate.sh" "$ROOT" "$TASK_ID" "$SKILL"

echo "$SKILL completed for task $TASK_ID"
exit 0
