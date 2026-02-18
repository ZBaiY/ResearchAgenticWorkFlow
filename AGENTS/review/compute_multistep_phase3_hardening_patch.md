# compute_algebraic_multistep phase3 hardening patch

## What changed
- Added per-task review token issuance on plan generation (`agenthub run` without `--execute` for multistep):
  - token file: `AGENTS/tasks/<TASK_ID>/work/review_token.txt`
  - progress state fields in `request_progress.json`:
    - `review_token`
    - `review_token_issued_at`
    - `review_ready_for_execute=false`
  - stdout marker: `REVIEW_TOKEN_ISSUED=true`
- Hardened `review-accept`:
  - now requires `--token <token>`
  - validates token using constant-time compare
  - success sets `REVIEW_READY_FOR_EXECUTE=true`
  - mismatch/missing token returns nonzero with:
    - `REVIEW_ACCEPTED=false`
    - `REVIEW_READY_FOR_EXECUTE=false`
    - `STOP_REASON=need_user_review`
- Hardened execute gate (`agenthub run --execute` for multistep):
  - blocked unless `review_ready_for_execute==true`
  - blocked stdout markers:
    - `EXECUTION_ALLOWED=false`
    - `STOP_REASON=need_user_review`
    - `REVIEW_READY_FOR_EXECUTE=false`
    - `HINT=Review gate not satisfied.`
- Plan regeneration resets gate and rotates token:
  - plan-only run resets `review_ready_for_execute=false` and issues new token
  - `plan-revise` also resets and reissues token

## Why this hardens Phase3
- External chaining `review-accept` + `--execute` without a valid task token is now blocked.
- Old tokens are invalidated after plan regeneration (token rotation), requiring fresh human review acknowledgment for each updated plan.
- `--execute` remains explicit and now additionally requires proof of review acceptance.

## Files changed
- `bin/agenthub`
- `tests/regression/compute_algebraic_multistep.sh`

## Tests run
- `python3 -m py_compile bin/agenthub`
- `tests/regression/compute_algebraic_multistep.sh`
- `tests/regression/compute_request_completion.sh`
- `tests/regression/compute_run_gate.sh`
