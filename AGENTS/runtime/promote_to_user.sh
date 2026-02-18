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
    y|yes) return 0 ;;
    n|no|"") return 1 ;;
    *)
      # Ask once more then default no.
      ans=""
      if { printf "%s" "$prompt" > /dev/tty && IFS= read -r ans < /dev/tty; } 2>/dev/null; then
        :
      fi
      ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
      case "$ans" in
        y|yes) return 0 ;;
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
    echo "noninteractive_requires_explicit_flags" >&2
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
import sys
from pathlib import PurePosixPath
from pathlib import Path

try:
    task_id = "$TASK_ID"
    src_required_prefix = f"GATE/staged/{task_id}/"

    def normalize_rel(raw: str, field_name: str) -> str:
        val = str(raw or "").strip()
        if not val:
            raise ValueError(f"missing {field_name}")
        p = PurePosixPath(val)
        if p.is_absolute():
            raise ValueError(f"{field_name} must be relative: {val}")
        if any(part in {"", ".", ".."} for part in p.parts):
            raise ValueError(f"{field_name} contains invalid segments: {val}")
        return p.as_posix()

    def normalize_prefix(raw: str) -> str:
        val = normalize_rel(raw, "allowed_dst_prefix")
        return val if val.endswith("/") else f"{val}/"

    p = Path("$PROMOTE_JSON")
    obj = json.loads(p.read_text(encoding="utf-8"))
    skill = str(obj.get("skill", "")).strip()
    maps = obj.get("mappings", [])
    raw_prefixes = obj.get("allowed_dst_prefixes", ["USER/"])
    if not isinstance(raw_prefixes, list) or not raw_prefixes:
        raise ValueError("allowed_dst_prefixes must be a non-empty list when present")
    allowed_dst_prefixes = tuple(normalize_prefix(x) for x in raw_prefixes)
    if not isinstance(maps, list):
        maps = []
    print(f"SKILL={skill}")
    for m in maps:
        if not isinstance(m, dict):
            continue
        src = normalize_rel(m.get("src", ""), "src")
        dst = normalize_rel(m.get("dst", ""), "dst")
        if not src.startswith(src_required_prefix):
            raise ValueError(f"src outside staged task boundary: {src}")
        if not any(dst.startswith(prefix) for prefix in allowed_dst_prefixes):
            raise ValueError(f"dst outside allowed USER boundary: {dst}")
        if src and dst:
            print(f"MAP={src}|{dst}")
except Exception as exc:
    print(f"mapping_validation_error: {exc}", file=sys.stderr)
    sys.exit(2)
PY
)" || {
  echo "Invalid promotion contract: mapping validation failed: $PROMOTE_JSON" >&2
  exit 2
}

SKILL="$(printf '%s\n' "$PROMOTE_ROWS" | sed -n 's/^SKILL=//p' | head -n1)"
if [[ -z "$SKILL" ]]; then
  echo "Invalid promotion contract (missing skill): $PROMOTE_JSON" >&2
  exit 2
fi

STAGE_ROOT_REAL="$(python3 - <<PY
from pathlib import Path
print(Path("$ROOT/GATE/staged/$TASK_ID").resolve(strict=True))
PY
)"
USER_ROOT_REAL="$(python3 - <<PY
from pathlib import Path
print(Path("$ROOT/USER").resolve(strict=True))
PY
)"

TARGETS=()
while IFS= read -r line; do
  [[ "$line" == MAP=* ]] || continue
  payload="${line#MAP=}"
  SRC_REL="${payload%%|*}"
  DST_REL="${payload#*|}"
  case "$SRC_REL" in
    GATE/staged/"$TASK_ID"/*) ;;
    *)
      echo "Invalid promotion mapping src boundary: $SRC_REL" >&2
      exit 2
      ;;
  esac
  case "$DST_REL" in
    USER/*) ;;
    *)
      echo "Invalid promotion mapping dst boundary: $DST_REL" >&2
      exit 2
      ;;
  esac
  SRC="$ROOT/$SRC_REL"
  DST="$ROOT/$DST_REL"
  [[ -f "$SRC" || -d "$SRC" ]] || { echo "Missing staged artifact: $SRC_REL" >&2; exit 2; }
  SRC_REAL="$(python3 - <<PY
from pathlib import Path
print(Path("$SRC").resolve(strict=True))
PY
)"
  case "$SRC_REAL" in
    "$STAGE_ROOT_REAL"/*) ;;
    *)
      echo "Invalid promotion source resolution: $SRC_REL" >&2
      exit 2
      ;;
  esac
  mkdir -p "$(dirname "$DST")"
  DST_PARENT_REAL="$(python3 - <<PY
from pathlib import Path
print(Path("$DST").parent.resolve(strict=True))
PY
)"
  case "$DST_PARENT_REAL" in
    "$USER_ROOT_REAL"|"$USER_ROOT_REAL"/*) ;;
    *)
      echo "Invalid promotion destination resolution: $DST_REL" >&2
      exit 2
      ;;
  esac
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
