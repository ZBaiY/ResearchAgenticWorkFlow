#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[1/4] no root duplicate prompt/run/schema files"
BAD_ROOT="$(find AGENTS/skills -mindepth 2 -maxdepth 2 -type f \( -name 'prompt.md' -o -name 'run.sh' -o -name 'schema.json' -o -name 'README.md' \) | rg -v '/(prompts|scripts|schemas|resources)/' || true)"
if [[ -n "$BAD_ROOT" ]]; then
  echo "FAIL: found root duplicate files"
  printf '%s\n' "$BAD_ROOT"
  exit 1
fi

echo "[2/4] canonical location for prompt/run/schema files"
CANON="$(find AGENTS/skills -maxdepth 3 -type f \( -name 'prompt.md' -o -name 'run.sh' -o -name 'schema.json' \) | rg -v '/prompts/prompt.md$|/scripts/run.sh$|/schemas/schema.json$' || true)"
if [[ -n "$CANON" ]]; then
  echo "FAIL: non-canonical prompt/run/schema files"
  printf '%s\n' "$CANON"
  exit 1
fi

echo "[3/4] every skill.yaml points to scripts/run.sh"
python3 - <<'PY'
from pathlib import Path
import re

for y in sorted(Path('AGENTS/skills').glob('*/skill.yaml')):
    txt = y.read_text(encoding='utf-8')
    m_run = re.search(r'^run:\s*(.+)$', txt, flags=re.M)
    m_prompt = re.search(r'^prompt:\s*(.+)$', txt, flags=re.M)
    m_schema = re.search(r'^schema:\s*(.+)$', txt, flags=re.M)
    if not m_run or m_run.group(1).strip() != 'scripts/run.sh':
        raise SystemExit(f'FAIL: invalid run path in {y}')
    if not m_prompt or m_prompt.group(1).strip() != 'prompts/prompt.md':
        raise SystemExit(f'FAIL: invalid prompt path in {y}')
    if not m_schema or m_schema.group(1).strip() != 'schemas/schema.json':
        raise SystemExit(f'FAIL: invalid schema path in {y}')
print('OK: skill.yaml paths are canonical')
PY

echo "[4/4] scripts/run.sh exists and is executable for every skill"
for s in AGENTS/skills/*; do
  [[ -d "$s" ]] || continue
  [[ -x "$s/scripts/run.sh" ]] || { echo "FAIL: missing executable $s/scripts/run.sh"; exit 1; }
done

echo "PASS: skill layout hygiene checks passed"
