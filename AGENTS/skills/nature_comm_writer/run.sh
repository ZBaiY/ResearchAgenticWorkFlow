#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="nature_comm_writer"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
USER_PAPER="$ROOT/USER/paper"
SHADOW_ROOT="$TDIR/work/paper_shadow"
SHADOW_PAPER="$SHADOW_ROOT/paper"
VENDOR_NATURE="$SHADOW_ROOT/vendor/nature"
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
RES_DIR="$ROOT/AGENTS/skills/nature_comm_writer/resources"
META_DIR="$RES_DIR/meta"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi
if [[ ! -d "$USER_PAPER" ]]; then
  echo "Missing required input directory: $USER_PAPER" >&2
  exit 2
fi

mkdir -p "$REVIEW_DIR" "$PATCH_DIR" "$LOG_DIR" "$SHADOW_ROOT" "$VENDOR_NATURE"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

run_cmd() {
  printf '%s\n' "$*" >> "$CMD_LOG"
  "$@"
}

run_cmd rsync -a --delete "$USER_PAPER/" "$SHADOW_PAPER/"

if [[ ! -d "$META_DIR" || -z "$(find "$META_DIR" -maxdepth 1 -name '*.json' -print -quit 2>/dev/null)" ]]; then
  echo "Resources metadata not found. Run: bash AGENTS/skills/nature_comm_writer/fetch_resources.sh" >> "$STDOUT_LOG"
fi

run_cmd rm -rf "$VENDOR_NATURE"
run_cmd mkdir -p "$VENDOR_NATURE"
for f in \
  "$RES_DIR/ncomms_for_authors.html" \
  "$RES_DIR/nature_reporting_standards.html" \
  "$RES_DIR/nature-latex-template.zip" \
  "$RES_DIR/GET_LATEX_TEMPLATE.md"; do
  if [[ -f "$f" ]]; then
    run_cmd cp "$f" "$VENDOR_NATURE/"
  fi
done

MAIN_TEX="$SHADOW_PAPER/main.tex"
PLACEHOLDER_COMMENT='% nature_comm_writer: placeholder run – no semantic edits applied'
EDITED=false
CREATED=false

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
  fi
else
  cat > "$MAIN_TEX" <<'EOF2'
% nature_comm_writer: placeholder run – no semantic edits applied
% Placeholder Nature Communications-style skeleton generated in shadow tree only.
\title{Placeholder Nature Communications Title}

\begin{abstract}
Placeholder abstract for a broad audience. Replace with manuscript-specific content.
\end{abstract}

\section{Introduction}
Placeholder introduction with motivation and context.

\section{Results}
Placeholder results narrative with figure-led explanation cues.

\section{Discussion}
Placeholder discussion of implications and limitations.

\section{Methods}
Placeholder methods summary.

\section*{Data availability}
TBD.

\section*{Code availability}
TBD.

\section*{References}
TBD.
EOF2
  CREATED=true
fi

HAS_RESULTS="false"
HAS_DISCUSSION="false"
if rg -q '\\section\*?\{[Rr]esults\}' "$MAIN_TEX"; then
  HAS_RESULTS="true"
fi
if rg -q '\\section\*?\{[Dd]iscussion\}' "$MAIN_TEX"; then
  HAS_DISCUSSION="true"
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

if [[ "$CREATED" == "true" ]]; then
  EDITED_JSON='[
    {
      "path": "main.tex",
      "change_type": "add",
      "purpose": "Create minimal Nature Communications placeholder skeleton in shadow tree",
      "risk_level": "low"
    }
  ]'
  NOTES='Placeholder mode with missing main.tex: created a minimal skeleton and no semantic edits.'
elif [[ "$EDITED" == "true" ]]; then
  EDITED_JSON='[
    {
      "path": "main.tex",
      "change_type": "edit",
      "purpose": "Insert deterministic placeholder comment at top of existing main.tex",
      "risk_level": "low"
    }
  ]'
  NOTES='Placeholder mode: inserted one header comment, no semantic edits.'
else
  EDITED_JSON='[]'
  NOTES='Placeholder mode: no changes required (header already present).'
fi

cat > "$MANIFEST" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "journal": "Nature Communications",
  "input_paper_root": "USER/paper",
  "shadow_root": "AGENTS/tasks/$TASK_ID/work/paper_shadow/paper",
  "edited_files": $EDITED_JSON,
  "narrative_notes": {
    "accessibility_actions": "Placeholder audit only: identify jargon/acronym density and define simplification pass.",
    "motivation_actions": "Placeholder audit only: strengthen why-now framing for broad audience.",
    "figure_story_actions": "Placeholder audit only: align each key claim with a figure-led explanation."
  },
  "section_structure": {
    "has_results_section": $HAS_RESULTS,
    "has_discussion_section": $HAS_DISCUSSION,
    "supplementary_references": []
  },
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
  echo "# nature_comm_writer Report"
  echo
  echo "- task_id: $TASK_ID"
  echo "- skill: $SKILL"
  echo "- journal focus: Nature Communications"
  echo
  echo "## Accessibility audit"
  echo "- Jargon/acronyms: placeholder mode; targeted simplification pass required."
  echo "- Assumed knowledge: verify background framing for broad readership."
  echo
  echo "## Narrative flow critique"
  echo "- Ensure Introduction establishes motivation before technical depth."
  echo "- Ensure Discussion interprets impact and limitations clearly."
  echo
  echo "## Figure–text alignment notes"
  echo "- Each major claim should cite and interpret the corresponding figure."
  echo "- Avoid purely procedural description without conceptual takeaway."
  echo
  echo "## Section-structure compliance notes"
  echo "- Results section present: $HAS_RESULTS"
  echo "- Discussion section present: $HAS_DISCUSSION"
  if [[ "$HAS_RESULTS" != "true" || "$HAS_DISCUSSION" != "true" ]]; then
    echo "- Missing required narrative section(s); revise structure before submission-oriented drafting."
  fi
  echo
  echo "## What would block a Nature referee"
  echo "- Unclear motivation and broad significance framing."
  echo "- Weak figure-to-claim explanation chain."
  echo "- Missing or underdeveloped Results/Discussion narrative structure."
  echo "- Overuse of unexplained acronyms and field-specific shorthand."
  echo
  echo "## Resources cached"
  if [[ -d "$META_DIR" ]]; then
    found="false"
    for meta in "$META_DIR"/*.json; do
      [[ -f "$meta" ]] || continue
      found="true"
      fname="$(basename "$meta" .json)"
      url="$(sed -n 's/^[[:space:]]*"url": "\(.*\)",$/\1/p' "$meta" | head -n 1)"
      status="$(sed -n 's/^[[:space:]]*"status": "\(.*\)",$/\1/p' "$meta" | head -n 1)"
      echo "- $fname (status: ${status:-unknown})"
      echo "  - path: AGENTS/skills/nature_comm_writer/resources/$fname"
      echo "  - url: ${url:-unknown}"
    done
    if [[ "$found" == "false" ]]; then
      echo "- No metadata JSON found. Run fetch_resources.sh."
    fi
  else
    echo "- No resources metadata directory found. Run fetch_resources.sh."
  fi
} > "$REPORT"

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  run_cmd git -C "$ROOT" status --porcelain
  git -C "$ROOT" status --porcelain > "$GIT_STATUS_LOG"
else
  echo "git not available or repo missing" > "$GIT_STATUS_LOG"
fi

bash "$ROOT/AGENTS/runtime/stage_to_gate.sh" "$ROOT" "$TASK_ID" "$SKILL"

echo "$SKILL completed for task $TASK_ID"
exit 0
