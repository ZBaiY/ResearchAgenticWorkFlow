# compute_multistep phase and latency patch

## What changed
- Removed schema-completion auto-plan trigger from `agenthub request-set` so schema completion no longer invokes skill runner.
  - `bin/agenthub:884`
- Kept schema boundary outputs machine-parseable and stop-oriented:
  - incomplete step: `STOP_REASON=need_user_input`
  - done step: `STOP_REASON=request_complete_waiting_user_run`
  - plan run: `STOP_REASON=need_user_review`
- Updated multistep regression expectations to enforce phase boundaries and no auto-plan-on-done.
  - `tests/regression/compute_algebraic_multistep.sh:95`
- Updated request-completion regression to match minimal done-state output (no extra prose line).
  - `tests/regression/compute_request_completion.sh:163`

## Why this matches contract
- Phase 1 now persists one field and stops; completion no longer transitions to plan automatically.
- Phase 2 plan generation is restored to explicit `agenthub run --task <TASK_ID>` only.
- Start/request-set no longer produce plan artifacts or execute work.
- No continuation tokens were introduced.

## Tests run
- `python3 -m py_compile bin/agenthub` ✅
- `tests/regression/compute_algebraic_multistep.sh` ✅
- `tests/regression/compute_request_completion.sh` ✅
- `tests/regression/compute_run_gate.sh` ✅
