# paper_profile_update

Role:
- Build/update a paper profile from local manuscript and notes.

Scope:
- Produce profile fields: keywords, categories/tags, short abstract blurb, related-work themes.
- Summarize profile updates in a human-readable report.

Data inputs:
- Read from `USER/paper/*.tex` and `USER/notes/*.md` when available.
- If no inputs are available, generate a deterministic placeholder profile with explicit notes.

Governance:
- Default: write only under `AGENTS/tasks/<task_id>/...`.
- Staging is optional and requires explicit consent to copy package into `GATE/staged/<task_id>/paper_profile_update/`.
- Never write to `USER/` by default.
- Optional exception: `write_to_user: true` in request plus exact interactive confirmation phrase `WRITE USER`.

Outputs:
- `AGENTS/tasks/<task_id>/review/paper_profile_update_report.md`
- `AGENTS/tasks/<task_id>/outputs/paper_profile/paper_profile.json`
- `AGENTS/tasks/<task_id>/logs/paper_profile_update/*`
