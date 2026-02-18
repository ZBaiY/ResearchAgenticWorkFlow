#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILL_DIR="$ROOT/AGENTS/skills/compute_algebraic"

[[ -f "$SKILL_DIR/skill.yaml" ]]
[[ -f "$SKILL_DIR/scripts/run.sh" ]]
[[ -f "$SKILL_DIR/prompts/prompt.md" ]]
[[ -f "$SKILL_DIR/templates/request.md" ]]
[[ -f "$SKILL_DIR/schemas/schema.json" ]]

echo "OK: compute_algebraic layout"
