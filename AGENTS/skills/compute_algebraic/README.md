---
OUTPUT POLICY (STRICT)
- Do NOT narrate. Do NOT write “I found / I’ll / Ran / Explored / Search…”.
- Do NOT echo shell scripts or commands (no “set -euo pipefail” or command blocks in output).
- Only print raw stdout/stderr of repo commands when necessary, and keep it minimal.
- For schema loops, print ONLY:
  REQUEST_STEP=...
  REQUEST_COMPLETE=...
  STOP_REASON=...
  <one question line + minimal example line>
- After ANY STOP_REASON, you MUST stop and ask the user. Forbidden: running additional commands in the same turn.
- Never use `set -x`.
- If you must run multiple commands, run them silently (redirect irrelevant output to /dev/null) and print only the required marker lines.
---

# compute_algebraic

Symbolic/algebraic compute skill using Wolfram Language.

## Contract
- Input source of truth: `AGENTS/tasks/<task_id>/request.json`
- Outputs: `AGENTS/tasks/<task_id>/work/...`
- Entry point: `AGENTS/skills/compute_algebraic/scripts/run.sh`
- Staging: `GATE/staged/<task_id>/compute_algebraic/...`
- Promotion: explicit via `agenthub promote`; no auto-run/auto-promote.

## Stepwise request filling
- Authoritative request schema is `AGENTS/tasks/<task_id>/request.json`.
- Start initializes `request.json` and `request_progress.json`, then stops.
- Fill fields in order: `goal` → `inputs` → `expected_outputs` → `constraints` → `preferred_formats`.
- `request_progress.json` tracks `current_step` and `updated_at` after every update.
- `run.sh` uses only `request.json`; if incomplete, run pauses for input (`need_input.md`) instead of failing.
