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

# jcap_writer

JCAP-specific LaTeX drafting/editing skill with shadow-copy safety and patch deliverables.

## Fetch resources

Populate/update the offline JCAP reference pack:

```bash
bash AGENTS/skills/jcap_writer/scripts/fetch_resources.sh
```

Cached resources and metadata live at:

- `AGENTS/skills/jcap_writer/resources/`
- `AGENTS/skills/jcap_writer/resources/meta/`

## Run via agentctl

```bash
agentctl new <task_name>
agentctl run jcap_writer --task <task_id>
```

## Outputs

Each run writes only under `AGENTS/tasks/<task_id>/...`:

- `work/paper_shadow/paper/` (shadow copy + edits)
- `work/paper_shadow/vendor/jcap/` (copied cached JCAP references)
- `review/jcap_writer_report.md`
- `deliverable/patchset/patch.diff`
- `deliverable/patchset/files_manifest.json`
- `logs/commands.txt`
- `logs/jcap_writer.stdout.log`
- `logs/jcap_writer.stderr.log`
- `logs/git_status.txt`

## Merge flow via GATE

1. Run `jcap_writer` to produce a patch against `USER/paper`.
2. Review report + manifest + patch under the task folder.
3. Manually move/apply patch artifacts through `GATE/` workflow.

The skill never modifies `USER/` or `GATE/` directly.
