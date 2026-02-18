# Silent Driver Policy Injection Postpatch Audit

## Files changed
- `bin/agenthub`
- `tests/regression/compute_algebraic_multistep.sh`

## What changed
- Updated compute constraints minimal example text in `bin/agenthub` to include both math assumptions and operational limits.
- Hardened multistep execute-block output in `bin/agenthub`:
  - removed blocked-path token echo (`REVIEW_TOKEN=...`) from stdout
  - replaced actionable review instruction with neutral marker line: `HINT=Review required.`
- Updated plan/revise plan-ready guidance lines to neutral: `Review required.`
- Kept schema completion message unchanged as required: `Say continue and we will start to plan.`
- Updated multistep regression checks to match the hardened, non-actionable review output.

## Tests updated
- `tests/regression/compute_algebraic_multistep.sh`
  - expects neutral review guidance (`Review required.` / `HINT=Review required.`)
  - no longer expects blocked execute to print `REVIEW_TOKEN=...`

## Tests run
- `tests/regression/compute_algebraic_multistep.sh` ✅
- `tests/regression/compute_request_completion.sh` ✅

## Contract confirmation
- Compute schema flow remains one-field-per-turn with stop markers.
- Schema completion does not auto-run plan.
- Default multistep run remains plan-only (`PLAN_STATUS=READY_FOR_REVIEW`, `EXECUTION_ALLOWED=false`, `STOP_REASON=need_user_review`).
- Execute remains gated by explicit review acceptance + explicit `--execute`.
- No repo code path auto-chains Phase2→Phase4; review/execute progression requires separate explicit CLI calls.

## Remaining ambiguity/failure modes
- External orchestrators can still choose to issue explicit follow-up commands; this patch reduces actionable stdout cues but cannot control out-of-repo drivers.
