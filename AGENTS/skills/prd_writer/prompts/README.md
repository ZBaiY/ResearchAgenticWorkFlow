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

# prd_writer

Create a structured Product Requirements Document (PRD) from task request/context files.

## Usage

```bash
agentctl new <task_name>
agentctl run prd_writer --task <task_id>
```

## Inputs

- Required: `AGENTS/tasks/<task_id>/request.md`
- Optional:
  - `AGENTS/tasks/<task_id>/work/context.md`
  - `AGENTS/tasks/<task_id>/work/context/*.md`

## Outputs

- `AGENTS/tasks/<task_id>/deliverable/prd/PRD.md`
- `AGENTS/tasks/<task_id>/deliverable/prd/PRD.json`
- `AGENTS/tasks/<task_id>/deliverable/prd/files_manifest.json`
- `AGENTS/tasks/<task_id>/review/prd_writer_report.md`
- `AGENTS/tasks/<task_id>/logs/commands.txt`
- `AGENTS/tasks/<task_id>/logs/prd_writer.stdout.log`
- `AGENTS/tasks/<task_id>/logs/prd_writer.stderr.log`
- `AGENTS/tasks/<task_id>/logs/git_status.txt`

## Governance boundaries

- Never modify `USER/`.
- `GATE/` writes are allowed only under `GATE/staged/` after explicit staging consent.
- Write only under `AGENTS/tasks/<task_id>/...`.
- This skill is project-contained and does not depend on globally installed skills.
