#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="jcap_writer"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
USER_PAPER="$ROOT/USER/paper"
SHADOW_ROOT="$TDIR/work/paper_shadow"
SHADOW_PAPER="$SHADOW_ROOT/paper"
VENDOR_JCAP="$SHADOW_ROOT/vendor/jcap"
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
RES_DIR="$ROOT/AGENTS/skills/jcap_writer/resources"
META_DIR="$RES_DIR/meta"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi

mkdir -p "$REVIEW_DIR" "$PATCH_DIR" "$LOG_DIR" "$SHADOW_ROOT" "$VENDOR_JCAP"
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

if [[ ! -d "$META_DIR" || -z "$(find "$META_DIR" -maxdepth 1 -name '*.json' -print -quit 2>/dev/null)" ]]; then
  echo "Resources metadata not found. Run: bash AGENTS/skills/jcap_writer/fetch_resources.sh" >> "$STDOUT_LOG"
fi

# Refresh vendor cache in shadow
run_cmd rm -rf "$VENDOR_JCAP"
run_cmd mkdir -p "$VENDOR_JCAP"

for f in \
  "$RES_DIR/jcap_texclass_help.html" \
  "$RES_DIR/JCAP-author-manual.pdf" \
  "$RES_DIR/jcappub.sty" \
  "$RES_DIR/template.tex" \
  "$RES_DIR/GET_THE_STYLE_PACKAGE.md"; do
  if [[ -f "$f" ]]; then
    run_cmd cp "$f" "$VENDOR_JCAP/"
  fi
done

# Copy any additional discovered style/template resources if present.
if compgen -G "$RES_DIR/*jcappub*.sty" > /dev/null; then
  for f in "$RES_DIR"/*jcappub*.sty; do
    run_cmd cp "$f" "$VENDOR_JCAP/"
  done
fi
if compgen -G "$RES_DIR/*template*.tex" > /dev/null; then
  for f in "$RES_DIR"/*template*.tex; do
    run_cmd cp "$f" "$VENDOR_JCAP/"
  done
fi

cat > "$REPORT" <<EOF2
# jcap_writer Report

- task_id: $TASK_ID
- skill: $SKILL
- journal: JCAP
- input_paper_root: USER/paper
- shadow_root: AGENTS/tasks/$TASK_ID/work/paper_shadow/paper

## Summary
- JCAP placeholder-safe run completed in shadow tree only.
- No semantic physics or data changes were attempted.

## JCAP Checklist
- title page info: include title, full author list, affiliations, and contact email where required.
- abstract/keywords/arxiv: ensure concise abstract, keywords, and arXiv number fields are present.
- bibliography style: use journal-compatible bibliography commands and consistent citation style.
- figure placement conventions: use clear captions, consistent labels, and avoid oversized floats.

## Edit Actions
EOF2

MAIN_TEX="$SHADOW_PAPER/main.tex"
MAIN_CHANGE_TYPE="none"
JCAP_PLACEHOLDER='% jcap_writer: placeholder run - no semantic edits applied'
STYLE_IN_VENDOR="false"

if compgen -G "$VENDOR_JCAP/*jcappub*.sty" > /dev/null; then
  STYLE_IN_VENDOR="true"
fi

if [[ -f "$MAIN_TEX" ]]; then
  FIRST_LINE="$(head -n 1 "$MAIN_TEX" || true)"
  if [[ "$FIRST_LINE" != "$JCAP_PLACEHOLDER" ]]; then
    TMP_FILE="$MAIN_TEX.tmp.$$"
    {
      printf '%s\n' "$JCAP_PLACEHOLDER"
      cat "$MAIN_TEX"
    } > "$TMP_FILE"
    mv "$TMP_FILE" "$MAIN_TEX"
    MAIN_CHANGE_TYPE="edit"
    echo "- Added placeholder header to existing main.tex" >> "$REPORT"
  else
    echo "- main.tex already marked with placeholder header" >> "$REPORT"
  fi
else
  cat > "$MAIN_TEX" <<EOF2
% jcap_writer: placeholder starter generated in shadow tree only.
\\documentclass[a4paper,11pt]{article}
% If JCAP style package is available in vendor/jcap, set TEXINPUTS accordingly.
EOF2
  if [[ "$STYLE_IN_VENDOR" == "true" ]]; then
    cat >> "$MAIN_TEX" <<'EOF2'
\usepackage{jcappub}
% Example build hint (shadow-only):
% TEXINPUTS=../vendor/jcap: latexmk -pdf main.tex
EOF2
  else
    cat >> "$MAIN_TEX" <<'EOF2'
% jcappub.sty not found in cached resources/vendor.
% Run: bash AGENTS/skills/jcap_writer/fetch_resources.sh
% Then copy official style files into AGENTS/skills/jcap_writer/resources/.
EOF2
  fi
  cat >> "$MAIN_TEX" <<'EOF2'

\title{Placeholder JCAP Title}
\author{Author Name}
\abstract{Placeholder abstract. Replace with manuscript-specific content.}
\keywords{placeholder, jcap}
\arxivnumber{0000.00000}

\begin{document}
\maketitle

\section{Introduction}
Placeholder introduction text.

\section{Conclusion}
Placeholder conclusion text.

% Bibliography placeholder
% \bibliographystyle{JHEP}
% \bibliography{refs}

\end{document}
EOF2
  MAIN_CHANGE_TYPE="add"
  echo "- Created placeholder main.tex in shadow because USER/paper/main.tex is absent" >> "$REPORT"
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

if [[ "$MAIN_CHANGE_TYPE" == "edit" ]]; then
  EDITED_JSON='[
    {
      "path": "main.tex",
      "change_type": "edit",
      "purpose": "Insert deterministic jcap_writer placeholder header",
      "risk_level": "low"
    }
  ]'
  NOTES='Placeholder mode with existing main.tex: added single non-semantic comment header.'
elif [[ "$MAIN_CHANGE_TYPE" == "add" ]]; then
  EDITED_JSON='[
    {
      "path": "main.tex",
      "change_type": "add",
      "purpose": "Create minimal JCAP placeholder starter in shadow tree",
      "risk_level": "low"
    }
  ]'
  NOTES='Placeholder mode without main.tex: created minimal starter main.tex in shadow tree.'
else
  EDITED_JSON='[]'
  NOTES='No content edits were required during placeholder mode.'
fi

cat > "$MANIFEST" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "journal": "JCAP",
  "input_paper_root": "USER/paper",
  "shadow_root": "AGENTS/tasks/$TASK_ID/work/paper_shadow/paper",
  "edited_files": $EDITED_JSON,
  "jcap_fit_notes": {
    "style_package_used": "$( [[ "$STYLE_IN_VENDOR" == "true" ]] && echo "jcappub available in vendor/jcap" || echo "jcappub unavailable; instructions left in main.tex" )",
    "toc_policy": "No forced TOC; keep structure concise unless user requests otherwise.",
    "bib_policy": "Preserve existing bibliography approach; do not alter scientific citations semantics.",
    "figure_policy": "Do not modify figures/data; only textual caption guidance in report."
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
  echo
  echo "## Resources Cached"
  if [[ -d "$META_DIR" ]]; then
    found_any="false"
    for meta in "$META_DIR"/*.json; do
      [[ -f "$meta" ]] || continue
      found_any="true"
      fname="$(basename "$meta" .json)"
      url="$(sed -n 's/^[[:space:]]*"url": "\(.*\)",$/\1/p' "$meta" | head -n 1)"
      status="$(sed -n 's/^[[:space:]]*"status": "\(.*\)",$/\1/p' "$meta" | head -n 1)"
      echo "- $fname (status: ${status:-unknown})"
      echo "  - path: AGENTS/skills/jcap_writer/resources/$fname"
      echo "  - url: ${url:-unknown}"
    done
    if [[ "$found_any" == "false" ]]; then
      echo "- No metadata JSON found. Run: bash AGENTS/skills/jcap_writer/fetch_resources.sh"
    fi
  else
    echo "- No resources/meta directory found. Run: bash AGENTS/skills/jcap_writer/fetch_resources.sh"
  fi

  echo
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

echo "$SKILL completed for task $TASK_ID"
exit 0
