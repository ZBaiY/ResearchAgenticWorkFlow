# paper_profile_update

Role:
- Build/update a high-quality paper profile from local manuscript, notes, and references.

Scope:
- Produce profile fields: field, field_confidence, evidence terms, keywords, n-grams, categories, short blurb, related-work themes.
- Build COMPLETE seed papers for downstream literature/writing skills.
- A COMPLETE seed must include: title, authors (>=1), arxiv_id or null, abstract (non-empty), link (http/https).
- Require at least 3 COMPLETE seed papers when seed sources exist; otherwise fail the run after exhaustive local attempts.
- Summarize profile updates and requirement status in a human-readable report.

Data inputs:
- Discovery order:
  1) `USER/paper/**` (main tex + recursive includes + bib directives)
  2) `USER/notes/**` (`.md/.tex/.txt`)
  3) `USER/references/for_seeds/**` (`.pdf/.txt/.md/.json`, prefer references over bib for seed ranking)
- Parse local `.bib` files and prioritize cited entries when scoring seeds.
- Default is local-only (no network). Online completion is only allowed with explicit `online_lookup: true` or run flag.
- Request config fields:
  - `online_lookup: false` (default)
  - `online_failfast: true` (default)
  - `min_complete_seeds: 3` (default)
  - If `online_lookup: true`, run with network enabled (`agenthub run --net`), otherwise fail fast.

Governance:
- Default: write only under `AGENTS/tasks/<task_id>/...`.
- Staging is optional and requires explicit consent to copy package into `GATE/staged/<task_id>/paper_profile_update/`.
- Never write to `USER/` by default.
- Optional exception: `write_to_user: true` in request plus exact interactive confirmation phrase `WRITE USER`.
- If online lookup is enabled and a network request fails, fail fast with `ERROR=NETWORK_LOOKUP_FAILED`.
- Failure handling contract:
  - If requirements are not met, stop immediately.
  - Do not perform additional repo exploration steps after failure.
  - Do not auto-enable online lookup unless explicitly requested.
  - Print only minimal failure summary to terminal:
    - `ERROR_CODE=...`
    - `MISSING=...` (if available)
    - `SEE=AGENTS/tasks/<task_id>/review/error.md`
    - `ACTION=...` (single next action)

Outputs:
- `AGENTS/tasks/<task_id>/review/paper_profile_update_report.md`
- `AGENTS/tasks/<task_id>/outputs/paper_profile/paper_profile.json`
- `AGENTS/tasks/<task_id>/logs/paper_profile_update/*`
