#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
TASK_ID="$2"
TDIR="$ROOT/AGENTS/tasks/$TASK_ID"

# Placeholder: you will replace this with an actual call to Codex/Claude/Gemini CLI.
# For now, we just create empty deliverables.
cat > "$TDIR/review/reading_list.md" <<'EOF2'
# Reading List (placeholder)

- [ ] Add papers here.
EOF2

cat > "$TDIR/review/refs.bib" <<'EOF2'
% refs.bib (placeholder)
EOF2

echo "literature_scout stub wrote:"
echo "  $TDIR/review/reading_list.md"
echo "  $TDIR/review/refs.bib"
