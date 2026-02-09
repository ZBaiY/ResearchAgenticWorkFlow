# Workflow Audit

## Implemented
- Skill discovery and deterministic ranking from metadata are implemented in `bin/agenthub` (`index`, `suggest`, score by `name/title/description/keywords`, deterministic tie ordering).
- Task bootstrap writes both request and metadata:
  - `AGENTS/tasks/<task_id>/request.md`
  - `AGENTS/tasks/<task_id>/meta.json`
  via `bin/agenthub start`.
- Run confirmations and key-value summary are implemented in `bin/agenthub run`:
  - confirmation notes from `skill.yaml`
  - explicit confirmation gate unless `--yes`
  - summary now includes `TASK`, `SKILL`, `PATCH`, `REPORT`, `RESULT`.
- Interactive minimal question layers exist for missing critical inputs:
  - `AGENTS/skills/literature_scout/run.py` asks retrieval method if absent and now asks `dossier_path` if absent; writes `AGENTS/tasks/<task_id>/logs/literature_scout/resolved_request.json` and `AGENTS/tasks/<task_id>/logs/method.json`.
  - `AGENTS/skills/slide_preparation/run.py` asks missing `duration_min`, `audience`, `venue`, `emphasis/goal` (<= 4 questions); writes `AGENTS/tasks/<task_id>/logs/slide_preparation/resolved_request.json`.
  - `AGENTS/skills/compute/run.sh` (deprecated router) asks backend selection when invoked and delegates to `compute_numerical` or `compute_symbolic`; writes `AGENTS/tasks/<task_id>/logs/compute/resolved_request.json`.
- Export-on-consent is implemented for code-producing skills:
  - `AGENTS/skills/compute_numerical/run.sh`
  - `AGENTS/skills/compute_symbolic/run.sh`
  Both prompt exactly: `Compute succeeded. Export a cleaned, commented program into deliverable/src? (y/N)` and record consent in `AGENTS/tasks/<task_id>/logs/compute/consent.json`.
- Manual promotion instructions (never direct USER writes by agents) are implemented:
  - `AGENTS/tasks/<task_id>/deliverable/promotion_instructions.md` for compute skills.
  - `AGENTS/tasks/<task_id>/deliverable/slides/promotion_instructions.md` for slide preparation.
- Cleanup policy implemented with failure preservation for compute:
  - success (`status=ok`): transient byproducts cleaned from `work/compute/run` and `work/compute/scratch`
  - non-success (`failed`/`backend_unavailable`): scratch/run preserved for forensics.
- `slide_preparation` cleanup is implemented in `AGENTS/skills/slide_preparation/run.py` (removes `work/slides/scratch` and `work/slides/build` after run).
- Natural-language bridge entrypoint added:
  - `bin/ask` (calls `agenthub suggest`, prints next exact `agenthub start` command and request template, does not execute runs).
- Skill contract completeness (`skill.yaml`, `run.sh`, `prompt.md`, `checks.sh`) now satisfied for all skill directories under `AGENTS/skills/`.

## Missing/Gaps
- No blocking gaps remain against the intended workflow source-of-truth.
- Residual caveat: `compute_symbolic` export-on-consent `y` path requires Wolfram backend availability (`wolframscript` or `math`). When unavailable, the skill intentionally returns `backend_unavailable` and cannot enter export prompt.

## Minimal Patch Plan
1. Add `dossier_path` prompt and resolved-request logging to literature scout.
2. Ensure compute cleanup preserves forensics on non-success; keep cleanup on success.
3. Route deprecated generic `compute` through explicit interactive backend selection and delegation.
4. Add `bin/ask` wrapper for natural-language to deterministic CLI handoff.
5. Ensure all skills include `checks.sh` and append concise terminal workflow section in `README.md`.
