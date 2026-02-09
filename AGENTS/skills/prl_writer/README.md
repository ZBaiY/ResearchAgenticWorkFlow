# prl_writer

PRL-style writing skill built on the same shadow-copy patch workflow as `latex_writer`.

## Usage

```bash
agentctl new <task_name>
agentctl run prl_writer --task <task_id>
```

## Outputs

For each run, artifacts are written under:

- `AGENTS/tasks/<task_id>/work/paper_shadow/paper/`
- `AGENTS/tasks/<task_id>/review/prl_writer_report.md`
- `AGENTS/tasks/<task_id>/deliverable/patchset/patch.diff`
- `AGENTS/tasks/<task_id>/deliverable/patchset/files_manifest.json`
- `AGENTS/tasks/<task_id>/logs/commands.txt`
- `AGENTS/tasks/<task_id>/logs/prl_writer.stdout.log`
- `AGENTS/tasks/<task_id>/logs/prl_writer.stderr.log`
- `AGENTS/tasks/<task_id>/logs/git_status.txt`

## Merge Flow

1. Run the skill to generate patch artifacts under `AGENTS/tasks/<task_id>/deliverable/patchset/`.
2. User reviews the PRL-focused report and diff.
3. User manually moves/applies patch artifacts to `GATE/` for downstream handling.

## Offline resources

This skill includes a cached offline references pack under:

- `AGENTS/skills/prl_writer/resources/`
- `AGENTS/skills/prl_writer/resources/meta/`

Refresh/download all assets with:

```bash
bash AGENTS/skills/prl_writer/fetch_resources.sh
```

Cached resources are used as writing references for:

- PRL length constraints and contributor expectations (`prl_info_for_contributors.html`)
- APS length guidance and REVTeX recommendation (`aps_length_guide.html`)
- REVTeX landing/FAQ references (`revtex_home.html`, `revtex_faq.html`)
- APS style consistency pointers (`aps_style_guide_authors.pdf`)
- REVTeX author/template assets (`apsguide4-2.pdf`, `apstemplate.tex`, `revtex-tds.zip`)
- Optional convenience starter (non-official): `prl_starter.tex`, using `\documentclass[prl,twocolumn]{revtex4-2}`

Each fetched file has provenance metadata at `resources/meta/<filename>.json` with URL, fetch time, sha256, bytes, and status.

These resources are references only; the skill must not modify `USER/` automatically.
