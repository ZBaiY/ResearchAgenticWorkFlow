#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[1/4] compute skill policy is ask_user"
rg -q '^clarification_policy:\s*ask_user$' AGENTS/skills/compute/skill.yaml || {
  echo "FAIL: compute clarification_policy is not ask_user"; exit 1;
}

echo "[2/4] Python helper obeys policy (ask_user prompts even with APPROVAL_MODE=no)"
OUT_PY_ASK="$(APPROVAL_MODE=no APPROVAL_INTERACTIVE=1 SKILL_CLARIFICATION_POLICY=ask_user PYTHONPATH=AGENTS/runtime python3 - <<'PY'
import io
import builtins
from unittest import mock
from approval import clarify_text

real_open = builtins.open
def fake_open(path, *args, **kwargs):
    if path == "/dev/tty":
        raise OSError("tty disabled for test")
    return real_open(path, *args, **kwargs)

with mock.patch('sys.stdin', io.StringIO('picked\n')), mock.patch('builtins.open', fake_open):
    print("\nVAL=" + clarify_text('Q: ', 'default'))
PY
)"
[[ "$(printf '%s\n' "$OUT_PY_ASK" | tail -n 1)" == "VAL=picked" ]] || { echo "FAIL: clarify_text did not prompt under ask_user"; exit 1; }

OUT_PY_AUTO="$(APPROVAL_MODE=no APPROVAL_INTERACTIVE=1 SKILL_CLARIFICATION_POLICY=auto PYTHONPATH=AGENTS/runtime python3 - <<'PY'
import io
import builtins
from unittest import mock
from approval import clarify_text

real_open = builtins.open
def fake_open(path, *args, **kwargs):
    if path == "/dev/tty":
        raise OSError("tty disabled for test")
    return real_open(path, *args, **kwargs)

with mock.patch('sys.stdin', io.StringIO('ignored\n')), mock.patch('builtins.open', fake_open):
    print("\nVAL=" + clarify_text('Q: ', 'default'))
PY
)"
[[ "$(printf '%s\n' "$OUT_PY_AUTO" | tail -n 1)" == "VAL=default" ]] || { echo "FAIL: clarify_text should default under auto"; exit 1; }

echo "[3/4] Shell helper obeys policy"
OUT_SH_ASK="$(printf 'picked_sh\n' | APPROVAL_MODE=no APPROVAL_INTERACTIVE=1 SKILL_CLARIFICATION_POLICY=ask_user bash -lc 'source AGENTS/runtime/approval.sh; approval_clarify_text "Q: " "default"')"
[[ "$OUT_SH_ASK" == "picked_sh" ]] || { echo "FAIL: approval_clarify_text did not prompt under ask_user"; exit 1; }

OUT_SH_AUTO="$(printf 'ignored_sh\n' | APPROVAL_MODE=no APPROVAL_INTERACTIVE=1 SKILL_CLARIFICATION_POLICY=auto bash -lc 'source AGENTS/runtime/approval.sh; approval_clarify_text "Q: " "default"')"
[[ "$OUT_SH_AUTO" == "default" ]] || { echo "FAIL: approval_clarify_text should default under auto"; exit 1; }

echo "[4/4] agenthub index exposes clarification policy field"
./bin/agenthub index >/tmp/clar_policy_index.out
python3 - <<'PY'
import json
from pathlib import Path
idx = json.loads(Path('AGENTS/runtime/skills_index.json').read_text())
skills = {s['name']: s for s in idx['skills']}
assert skills['compute']['clarification_policy'] == 'ask_user'
assert skills['paper_profile_update']['clarification_policy'] in {'auto', ''}
print('OK')
PY

echo "PASS: clarification policy regression checks passed"
