# compute_algebraic_multistep phase3 gate patch

## Files changed
- `bin/agenthub`
- `tests/regression/compute_algebraic_multistep.sh`

## Rationale and changes
- Kept schema loop behavior unchanged (one-field-per-turn) and retained completion marker block.
- Kept schema completion sentence as:
  - `Say continue and we will start to plan.`
- Kept constraints example aligned with mathematical + operational constraints for multistep:
  - `MIN_EXAMPLE: assumptions: a>0, x in Reals; limits: time<10s; tools: local symbolic only; network: none`
- Hardened Phase3->Phase4 gate:
  - plan-only run now issues a short review token (`8` hex chars) and rotates it whenever plan is regenerated.
  - blocked execute now returns:
    - `EXECUTION_ALLOWED=false`
    - `STOP_REASON=need_user_review`
    - `REVIEW_READY_FOR_EXECUTE=false`
    - `REVIEW_TOKEN=<token>`
    - `Review plan. When ready, run review-accept with token.`
  - `review-accept` requires `--token` and validates token via constant-time compare.
  - execute allowed only after valid `review-accept`.

## Tests updated
- `tests/regression/compute_algebraic_multistep.sh`
  - asserts old sentence is absent (`Say continue to run and I’ll execute it.`)
  - asserts updated completion sentence is present
  - asserts blocked execute includes review token
  - asserts review token rotation and stale-token rejection after plan regeneration

## Commands run
- `python3 -m py_compile bin/agenthub`
- `tests/regression/compute_algebraic_multistep.sh`
- `tests/regression/compute_request_completion.sh`
- `tests/regression/compute_run_gate.sh`

All passed.
