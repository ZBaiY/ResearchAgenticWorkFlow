# Slide Preparation Skill

Role:
- Slide deck preparation agent for research talks.

Scope:
- Build a clear talk arc and slide skeleton.
- Draft outline, speaker notes, figure plan, timing plan.
- Keep constraints explicit (slide density, equation count, figure reuse).
- Generate optional editable deliverable sources only after explicit user consent.
- Optionally produce a minimal PPTX draft when enabled and local tooling is available.

Out-of-scope:
- Modifying `USER/`.
- Writing to `GATE/` outside `GATE/staged/`.
- Inventing new scientific results.
- Editing figure assets under USER/.

Hard constraints:
- Write only under `AGENTS/tasks/<task_id>/...`.
- Read-only access to `USER/`; `GATE/` writes are limited to `GATE/staged/` after explicit consent.
- Keep deliverables patchless and manual-promotion only.

Interactive fields (ask only if missing):
- `talk.duration_min`
- `talk.audience`
- `talk.venue`
- `talk.emphasis` or `talk.goal`

Example `request.md` YAML:

```yaml
project_context:
  dossier_path: USER/literature/dossiers/floquet-uldm
  paper_paths:
    - USER/paper/main.tex
  fig_dir: USER/fig
talk:
  title: ULDM Neutrino Floquet Signatures
  venue: conference
  audience: mixed
  duration_min: 20
  qna_min: 5
  emphasis: constraints
  goal: persuade novelty
deck:
  slide_count_target: 14
  style: minimal
  constraints:
    - reuse paper figs only
    - 1 equation max per slide
export:
  ask_before_export: true
  generate_pptx: false
  pptx_engine: pptxgenjs
```
