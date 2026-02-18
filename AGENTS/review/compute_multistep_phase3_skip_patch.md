# compute_algebraic_multistep phase3-skip patch

## Files changed
- `bin/agenthub`
- `tests/regression/compute_algebraic_multistep.sh`

## What changed
- Added task-local review latch in `request_progress.json`:
  - key: `review_ready_for_execute` (default `false`).
- Added `agenthub review-accept --task <TASK_ID>`:
  - sets latch true and prints:
    - `REVIEW_ACCEPTED=true`
    - `REVIEW_READY_FOR_EXECUTE=true`
    - `STOP_REASON=request_complete_waiting_user_execute`
- Enforced execute gate in `agenthub run` for `compute_algebraic_multistep`:
  - `--execute` is blocked unless latch is true.
  - blocked output:
    - `EXECUTION_ALLOWED=false`
    - `STOP_REASON=need_user_review`
    - `REVIEW_READY_FOR_EXECUTE=false`
    - `HINT=Review plan first, then acknowledge with review-accept.`
  - returns exit code 0 and does not run skill when blocked.
- Reset latch on plan regeneration:
  - in plan-only `agenthub run` path for multistep (`--execute` absent), latch is set back to `false` before dispatch.
  - `plan-revise` also resets latch to `false`.

## Why this fixes Phase3-skip
- Execution can no longer proceed immediately after schema completion by passing `--execute`.
- Human must explicitly acknowledge plan review via `review-accept` before execution is allowed.
- Any subsequent plan regeneration invalidates prior acceptance and requires re-acceptance.

## How to use review-accept
1. Run plan-only:
   - `agenthub run --task <TASK_ID>`
2. Review plan artifacts.
3. Acknowledge review:
   - `agenthub review-accept --task <TASK_ID>`
4. Execute:
   - `agenthub run --task <TASK_ID> --execute`

## Tests run
- `python3 -m py_compile bin/agenthub`
- `tests/regression/compute_algebraic_multistep.sh`
- `tests/regression/compute_request_completion.sh`
- `tests/regression/compute_run_gate.sh`
