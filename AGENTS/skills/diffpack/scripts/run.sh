#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
TASK_ID="$2"
TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
OUT="$TDIR/deliverable/patchset"

mkdir -p "$OUT"
cat > "$OUT/README.md" <<'EOF2'
# patchset (placeholder)

Put your generated diffs here, e.g. `patch.diff`, plus a manifest.

Recommended:
- patch.diff
- files_manifest.json
- apply.sh (applies patch to GATE, not USER)
EOF2

echo "diffpack stub prepared:"
echo "  $OUT/README.md"
