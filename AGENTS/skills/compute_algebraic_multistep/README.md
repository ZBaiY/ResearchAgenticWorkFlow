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

Symbolic multistep computation skill with human-reviewed planning.

## Workflow
- Start creates scaffold plus `request.json`/`request_progress.json`, then stops.
- Request collection is stepwise via `agenthub request-set`.
- When the final schema field is submitted, plan generation runs automatically in plan-only mode and stops for review.
- If request schema is incomplete, `run` pauses for input and writes `review/need_input.md` (no error exit).
- `agenthub run --task <id>` generates `plan.json` + `report_plan.md` only.
- `agenthub run --task <id> --execute` executes plan steps with Wolfram backend.
- Outputs are staged to `GATE/staged/<task_id>/compute_algebraic_multistep/`.
- Promotion is explicit and separate.

## Output hygiene
- Normal mode suppresses tool-trace/debug envelope lines from user-visible output.
- Filtered lines are written to `AGENTS/tasks/<task_id>/review/trace_debug.log`.

## Request schema source of truth
- `AGENTS/tasks/<task_id>/request.json` is authoritative.
- Includes: `goal`, `inputs`, `expected_outputs`, `constraints`, `preferred_formats`, `policy`.

## Policy defaults
```json
{
  "max_steps": 8,
  "time_limit_sec_per_step": 10,
  "max_leaf_count": 50000,
  "assumptions": "",
  "check_level": "equivalence",
  "allowlist_ops": [
    "Simplify","FullSimplify","Assuming","Refine","Together",
    "Factor","Apart","FunctionExpand","TrigReduce","Series",
    "Normal","Solve","Reduce","Integrate","D"
  ]
}
```
