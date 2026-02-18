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

# nature_comm_writer

Nature Communications-oriented LaTeX drafting/editing skill.

## How this differs from PRL/JHEP writer

- Focuses on broad-audience narrative clarity and motivation.
- Emphasizes figure-led storytelling and conceptual accessibility.
- Prioritizes clear Introduction/Results/Discussion structure and referee-facing readability.
- Does not assume PRL/JHEP style or formatting conventions.

## Offline resources

Fetch/update cached official references:

```bash
bash AGENTS/skills/nature_comm_writer/scripts/fetch_resources.sh
```

Cached resources and metadata:

- `AGENTS/skills/nature_comm_writer/resources/`
- `AGENTS/skills/nature_comm_writer/resources/meta/`

Intended usage:

- `ncomms_for_authors.html`: author policy and submission guidance anchor.
- `nature_reporting_standards.html`: reporting standards reference.
- `nature-latex-template.zip` (if available): official template pack.
- `GET_LATEX_TEMPLATE.md`: manual fallback instructions when direct link is not confidently discoverable.

## Run via agentctl

```bash
agentctl new <task_name>
agentctl run nature_comm_writer --task <task_id>
```

## Outputs and merge flow

Each run writes only under `AGENTS/tasks/<task_id>/...`:

- `work/paper_shadow/paper/`
- `work/paper_shadow/vendor/nature/`
- `review/nature_comm_writer_report.md`
- `deliverable/patchset/patch.diff`
- `deliverable/patchset/files_manifest.json`
- logs under `logs/`

Patch artifacts are reviewed and merged manually through `GATE/` workflow; this skill never modifies `USER/` or `GATE/` directly.
