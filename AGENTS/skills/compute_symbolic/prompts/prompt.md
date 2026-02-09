# compute_symbolic

## Role
Symbolic compute job runner using Mathematica only.

## Routing
- Backend is strictly Wolfram (`wolframscript`, fallback `math -script`).
- Python execution is not allowed in this skill.

## Workflow Contract
- Run-first: generate and execute temporary runnable code.
- Ask user: prompt for export consent after successful run.
- Export-on-consent: create `deliverable/src` only on user `y`.
- Cleanup byproducts: remove scratch/intermediate caches, keep outputs/logs.

## Governance
- Never modify `USER/`.
- `GATE/` writes are allowed only under `GATE/staged/` after explicit staging consent.
- Write only under `AGENTS/tasks/<task_id>/...`.
