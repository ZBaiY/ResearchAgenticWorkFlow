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

# compute_algebraic_multistep

Generate a reviewed symbolic computation plan first, then execute only when `COMPUTE_EXECUTE=1`.

Requirements:
- Request source of truth: `AGENTS/tasks/<task_id>/request.json`.
- Plan mode (default): produce `work/src/plan.json`, `work/src/steps/step_XX.wl`, `work/report_plan.md`, and stop.
- Execute mode (`COMPUTE_EXECUTE=1`): run each step under policy limits, emit `work/out/step_XX.json`, `work/report_execute.md`, and `work/report.md`.
- Never write to `USER/` during run.
