# Metadata Design Note

## Current staging paths
- Staged artifacts are written only under `GATE/staged/<task_id>/<skill_name>/`.
- Task-level stage instructions are written to `GATE/staged/<task_id>/STAGE.md`.

## Current consent logs
- Stage consent is recorded per skill run at:
  - `AGENTS/tasks/<task_id>/logs/<skill_name>/stage_consent.json`
- Compute export consent is recorded at:
  - `AGENTS/tasks/<task_id>/logs/compute/consent.json`
- Slide export consent is recorded at:
  - `AGENTS/tasks/<task_id>/logs/slide_preparation/consent.json`

## USER-write prevention today
- Skill outputs are generated under `AGENTS/tasks/<task_id>/...`.
- Optional staging copies only into `GATE/staged/...` after explicit prompt consent.
- Promotion into `USER/` is provided as manual commands in stage/promotion notes, not auto-applied.

## Reusable patterns for metadata updates
- Reuse per-skill logs directory pattern: `AGENTS/tasks/<task_id>/logs/<skill>/...`.
- Reuse explicit consent prompts before staging/export operations.
- Reuse staged package pattern under `GATE/staged/<task_id>/<skill>/` with a short `STAGE.md` containing manual promotion commands.
- Reuse deterministic JSON outputs plus sha256 logging for traceability.
