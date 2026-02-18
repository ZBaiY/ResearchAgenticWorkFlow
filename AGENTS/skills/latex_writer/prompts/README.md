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

# latex_writer

Generic LaTeX drafting/editing skill with shadow-copy safety.

## Usage

```bash
agentctl new <task_name>
agentctl run latex_writer --task <task_id>
```

## Outputs

For each run, artifacts are written under:

- `AGENTS/tasks/<task_id>/work/paper_shadow/paper/`
- `AGENTS/tasks/<task_id>/review/latex_writer_report.md`
- `AGENTS/tasks/<task_id>/deliverable/patchset/patch.diff`
- `AGENTS/tasks/<task_id>/deliverable/patchset/files_manifest.json`
- `AGENTS/tasks/<task_id>/logs/commands.txt`
- `AGENTS/tasks/<task_id>/logs/latex_writer.stdout.log`
- `AGENTS/tasks/<task_id>/logs/latex_writer.stderr.log`
- `AGENTS/tasks/<task_id>/logs/git_status.txt`

## Merge Flow

1. Run the skill to generate patch artifacts under `AGENTS/tasks/<task_id>/deliverable/patchset/`.
2. User reviews the report and diff.
3. User manually moves/applies patch artifacts to `GATE/` for downstream handling.
