#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="prd_writer"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: checks.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
PRD_MD="$TDIR/deliverable/prd/PRD.md"
REPORT="$TDIR/review/${SKILL}_report.md"
LOG_DIR="$TDIR/logs"

mkdir -p "$LOG_DIR"

USER_GATE_STATUS="skipped"
PRD_STATUS="missing"
HEADERS_STATUS="fail"
REQ_UNIQUE_STATUS="fail"
AC_MAP_STATUS="fail"

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$ROOT" status --porcelain | rg -q '^(.. )?(USER/|GATE/)'; then
    USER_GATE_STATUS="fail"
  else
    USER_GATE_STATUS="ok"
  fi
fi

if [[ -f "$PRD_MD" ]]; then
  PRD_STATUS="ok"
fi

if [[ "$PRD_STATUS" == "ok" ]]; then
  HEADERS=(
    "## 0. Metadata"
    "## 1. Problem statement"
    "## 2. Goals"
    "## 3. Non-goals"
    "## 4. Users & use cases"
    "## 5. Requirements"
    "## 6. Interfaces & integration"
    "## 7. Success metrics"
    "## 8. Acceptance criteria"
    "## 9. Risks & mitigations"
    "## 10. Open questions"
    "## 11. Milestones"
    "## 12. Appendix"
  )

  prev=0
  ok_order="true"
  for h in "${HEADERS[@]}"; do
    line="$(rg -nF "$h" "$PRD_MD" | head -n 1 | cut -d: -f1)"
    if [[ -z "$line" ]]; then
      ok_order="false"
      break
    fi
    if [[ "$line" -le "$prev" ]]; then
      ok_order="false"
      break
    fi
    prev="$line"
  done

  if [[ "$ok_order" == "true" ]]; then
    HEADERS_STATUS="ok"
  fi

  REQ_IDS=()
  while IFS= read -r req; do
    [[ -n "$req" ]] && REQ_IDS+=("$req")
  done < <(sed -nE 's/^[[:space:]]*-[[:space:]]*((FR|NFR)-[0-9]{3}):.*/\1/p' "$PRD_MD")

  if [[ "${#REQ_IDS[@]}" -eq 0 ]]; then
    REQ_UNIQUE_STATUS="ok"
  else
    dups="$(printf '%s\n' "${REQ_IDS[@]}" | sort | uniq -d || true)"
    if [[ -z "$dups" ]]; then
      REQ_UNIQUE_STATUS="ok"
    fi
  fi

  AC_REFS=()
  while IFS= read -r ref; do
    [[ -n "$ref" ]] && AC_REFS+=("$ref")
  done < <(rg -o '\[(FR|NFR)-[0-9]{3}\]' "$PRD_MD" | tr -d '[]')

  if [[ "${#REQ_IDS[@]}" -eq 0 ]]; then
    AC_MAP_STATUS="ok"
  else
    if [[ "${#AC_REFS[@]}" -eq 0 ]]; then
      AC_MAP_STATUS="fail"
    else
      missing="false"
      for ref in "${AC_REFS[@]}"; do
        found="false"
        for req in "${REQ_IDS[@]}"; do
          if [[ "$ref" == "$req" ]]; then
            found="true"
            break
          fi
        done
        if [[ "$found" == "false" ]]; then
          missing="true"
          break
        fi
      done
      if [[ "$missing" == "false" ]]; then
        AC_MAP_STATUS="ok"
      fi
    fi
  fi
fi

{
  echo
  echo "## checks.sh"
  echo "- USER/GATE unchanged check: $USER_GATE_STATUS"
  echo "- PRD.md exists: $PRD_STATUS"
  echo "- Heading order valid: $HEADERS_STATUS"
  echo "- Requirement IDs unique: $REQ_UNIQUE_STATUS"
  echo "- Acceptance criteria mapping valid: $AC_MAP_STATUS"
} >> "$REPORT"

echo "USER_GATE_STATUS=$USER_GATE_STATUS"
echo "PRD_STATUS=$PRD_STATUS"
echo "HEADERS_STATUS=$HEADERS_STATUS"
echo "REQ_UNIQUE_STATUS=$REQ_UNIQUE_STATUS"
echo "AC_MAP_STATUS=$AC_MAP_STATUS"

if [[ "$USER_GATE_STATUS" == "fail" || "$PRD_STATUS" != "ok" || "$HEADERS_STATUS" != "ok" || "$REQ_UNIQUE_STATUS" != "ok" || "$AC_MAP_STATUS" != "ok" ]]; then
  exit 1
fi

exit 0
