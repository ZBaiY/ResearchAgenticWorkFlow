#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILL_DIR="$ROOT/AGENTS/skills/compute_algebraic_multistep"

test -f "$SKILL_DIR/skill.yaml"
test -f "$SKILL_DIR/README.md"
test -f "$SKILL_DIR/prompts/prompt.md"
test -f "$SKILL_DIR/schemas/schema.json"
test -f "$SKILL_DIR/templates/request.json.template"
test -x "$SKILL_DIR/scripts/run.sh"

echo "OK: compute_algebraic_multistep layout"
