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

# Request

Goal:
{{GOAL}}

Constraints:
- Keep computation deterministic.
- Keep outputs under AGENTS/tasks/<task_id>/work/.
- No USER writes during run.

Expected Deliverables:
- Generated Python source.
- Structured numeric outputs.
- Optional figures under work/fig/.
- report.md with all required sections.

Inputs (JSON):
```json
{
  "goal": "{{GOAL}}",
  "inputs": {
    "mode": "quadratic_scan",
    "x_values": [-3, -2, -1, 0, 1, 2, 3],
    "coefficients": {
      "a": 1.0,
      "b": -2.0,
      "c": 1.0
    },
    "make_plot": false
  },
  "expected_outputs": {
    "result_file": "result.json",
    "figure_file": "quadratic_scan.png"
  },
  "constraints": [
    "Use Python only",
    "No network access"
  ],
  "preferred_formats": [
    "json",
    "png"
  ]
}
```
