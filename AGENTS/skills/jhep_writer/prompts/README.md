# jhep_writer

JHEP-specific LaTeX drafting/editing skill with shadow-copy safety and patch deliverables.

## Offline resources

Populate/update the offline JHEP reference pack:

```bash
bash AGENTS/skills/jhep_writer/scripts/fetch_resources.sh
```

Cached resources and metadata live at:

- `AGENTS/skills/jhep_writer/resources/`
- `AGENTS/skills/jhep_writer/resources/meta/`

Primary cached references:

- `resources/jhep_texclass.html`
- `resources/jhep_author_manual.pdf`
- optional style/template assets when explicitly linked from official JHEP page

Each fetched file has provenance metadata in `resources/meta/<filename>.json` with URL, fetch time, sha256, bytes, and status.

## Run via agentctl

```bash
agentctl new <task_name>
agentctl run jhep_writer --task <task_id>
```

## Outputs

Each run writes only under `AGENTS/tasks/<task_id>/...`:

- `work/paper_shadow/paper/` (shadow copy + edits)
- `work/paper_shadow/vendor/jhep/` (copied cached JHEP references)
- `review/jhep_writer_report.md`
- `deliverable/patchset/patch.diff`
- `deliverable/patchset/files_manifest.json`
- `logs/commands.txt`
- `logs/jhep_writer.stdout.log`
- `logs/jhep_writer.stderr.log`
- `logs/git_status.txt`

## Merge flow via GATE

1. Run `jhep_writer` to produce a patch against `USER/paper`.
2. Review report + manifest + patch under the task folder.
3. Manually move/apply patch artifacts through `GATE/` workflow.

The skill never modifies `USER/` or `GATE/` directly.
