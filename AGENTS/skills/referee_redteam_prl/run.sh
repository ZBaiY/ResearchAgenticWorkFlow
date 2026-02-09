#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
TASK_ID="$2"
TDIR="$ROOT/AGENTS/tasks/$TASK_ID"

cat > "$TDIR/review/referee_report.md" <<'EOF2'
# Referee Report (placeholder)

## Major issues
- ...

## Minor issues
- ...

## Notation consistency
- ...
EOF2

echo "referee_redteam_prl stub wrote:"
echo "  $TDIR/review/referee_report.md"
