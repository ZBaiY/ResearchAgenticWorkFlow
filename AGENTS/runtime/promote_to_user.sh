#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASK_ID=""
FLAG_YES=0
FLAG_NO=0
ALLOW_NONINTERACTIVE=0

is_tty() {
  [[ -t 0 ]]
}

prompt_yes_no_fuzzy() {
  local prompt="${1:-Promote staged outputs to USER? [y/N] }"
  local ans=""
  if [[ -r /dev/tty ]]; then
    if { printf "%s" "$prompt" > /dev/tty && IFS= read -r ans < /dev/tty; } 2>/dev/null; then
      :
    fi
  else
    return 1
  fi
  ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
  case "$ans" in
    y|yes|yeah|ok|sure|1|promote) return 0 ;;
    n|no|stop|0|cancel|"") return 1 ;;
    *)
      # Ask once more then default no.
      ans=""
      if { printf "%s" "$prompt" > /dev/tty && IFS= read -r ans < /dev/tty; } 2>/dev/null; then
        :
      fi
      ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
      case "$ans" in
        y|yes|yeah|ok|sure|1|promote) return 0 ;;
      esac
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      TASK_ID="${2:-}"
      shift 2
      ;;
    --yes)
      FLAG_YES=1
      shift
      ;;
    --no)
      FLAG_NO=1
      shift
      ;;
    --allow-user-write-noninteractive)
      ALLOW_NONINTERACTIVE=1
      shift
      ;;
    *)
      echo "Usage: AGENTS/runtime/promote_to_user.sh --task <task_id> [--yes|--no] [--allow-user-write-noninteractive]" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$TASK_ID" ]]; then
  echo "Usage: AGENTS/runtime/promote_to_user.sh --task <task_id> [--yes|--no] [--allow-user-write-noninteractive]" >&2
  exit 2
fi

if [[ "$FLAG_YES" -eq 1 && "$FLAG_NO" -eq 1 ]]; then
  echo "ERROR=Use only one of --yes or --no." >&2
  exit 2
fi

if [[ "$FLAG_NO" -eq 1 ]]; then
  echo "Promotion skipped"
  exit 0
fi

if is_tty; then
  if [[ "$FLAG_YES" -ne 1 ]]; then
    if ! prompt_yes_no_fuzzy "Promote staged outputs to USER? [y/N] "; then
      echo "Promotion skipped"
      exit 0
    fi
  fi
else
  if [[ "$FLAG_YES" -ne 1 || "$ALLOW_NONINTERACTIVE" -ne 1 ]]; then
    echo "NEXT=./AGENTS/runtime/promote_to_user.sh --task $TASK_ID --yes --allow-user-write-noninteractive" >&2
    exit 2
  fi
fi

STAGE_TASK_DIR="$ROOT/GATE/staged/$TASK_ID"
if [[ ! -d "$STAGE_TASK_DIR" ]]; then
  echo "Missing staged task directory: $STAGE_TASK_DIR" >&2
  exit 2
fi

PROMOTE_JSON="$STAGE_TASK_DIR/PROMOTE.json"
if [[ ! -f "$PROMOTE_JSON" ]]; then
  echo "Missing promotion contract: $PROMOTE_JSON" >&2
  exit 2
fi

PROMOTE_ROWS="$(python3 - <<PY
import json
from pathlib import Path
p = Path("$PROMOTE_JSON")
obj = json.loads(p.read_text(encoding="utf-8"))
skill = str(obj.get("skill", "")).strip()
maps = obj.get("mappings", [])
if not isinstance(maps, list):
    maps = []
print(f"SKILL={skill}")
for m in maps:
    if not isinstance(m, dict):
        continue
    src = str(m.get("src", "")).strip()
    dst = str(m.get("dst", "")).strip()
    if src and dst:
        print(f"MAP={src}|{dst}")
PY
)"

SKILL="$(printf '%s\n' "$PROMOTE_ROWS" | sed -n 's/^SKILL=//p' | head -n1)"
if [[ -z "$SKILL" ]]; then
  echo "Invalid promotion contract (missing skill): $PROMOTE_JSON" >&2
  exit 2
fi

TARGETS=()
while IFS= read -r line; do
  [[ "$line" == MAP=* ]] || continue
  payload="${line#MAP=}"
  SRC_REL="${payload%%|*}"
  DST_REL="${payload#*|}"
  SRC="$ROOT/$SRC_REL"
  DST="$ROOT/$DST_REL"
  [[ -f "$SRC" || -d "$SRC" ]] || { echo "Missing staged artifact: $SRC_REL" >&2; exit 2; }
  mkdir -p "$(dirname "$DST")"
  if [[ -d "$SRC" ]]; then
    cp -R "$SRC" "$DST"
  else
    cp "$SRC" "$DST"
  fi
  TARGETS+=("$DST_REL")
done <<< "$PROMOTE_ROWS"

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "Invalid promotion contract (no mappings): $PROMOTE_JSON" >&2
  exit 2
fi

RECEIPT_DIR="$ROOT/USER/manifest/promotion_receipts"
mkdir -p "$RECEIPT_DIR"
TS="$(date -u +"%Y%m%dT%H%M%SZ")"
RECEIPT="$RECEIPT_DIR/${TASK_ID}_${TS}.json"
cat > "$RECEIPT" <<EOF
{
  "timestamp_utc": "$TS",
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "from": "GATE/staged/$TASK_ID",
  "targets": [
    "${TARGETS[0]}"
  ]
}
EOF

for p in "${TARGETS[@]}"; do
  echo "PROMOTED_TARGET=$p"
done
echo "PROMOTION_RECEIPT=${RECEIPT#$ROOT/}"
