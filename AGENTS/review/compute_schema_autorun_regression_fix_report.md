compute schema autorun regression fix report

files changed
- bin/agenthub
- bin/a
- tests/regression/compute_request_completion.sh
- tests/regression/compute_run_gate.sh
- tests/regression/compute_algebraic_multistep.sh

exact STOP markers added
- request-set path (`bin/agenthub`):
  - `STOP_REASON=need_user_input` when `REQUEST_COMPLETE=false`
  - `STOP_REASON=request_complete_waiting_user_run` when `REQUEST_COMPLETE=true`
- compute start schema prompt path (`bin/agenthub`):
  - `STOP_REASON=need_user_input`
- compute run incomplete gate (`bin/agenthub`):
  - `STOP_REASON=need_user_input`
- bart compute early-return gate (`bin/a`):
  - `STOP_REASON=need_user_input`

schema UX output changes
- for every incomplete schema boundary, output now includes:
  - one question line
  - one `MIN_EXAMPLE: ...` line
- for completed request-set state, output now includes exactly:
  - `REQUEST_STEP=done`
  - `REQUEST_COMPLETE=true`
  - `STOP_REASON=request_complete_waiting_user_run`
  - `If you want execution, explicitly say run.`

regression tests added/updated
- `tests/regression/compute_request_completion.sh`
  - validates STOP markers on each step
  - validates exactly one MIN_EXAMPLE line for incomplete states
  - validates forbidden token checks on MIN_EXAMPLE
  - validates complete-state sentence and no MIN_EXAMPLE
  - validates no auto execution artifact before explicit run
- `tests/regression/compute_run_gate.sh`
  - validates pick/start/run pause STOP contract markers
  - validates exactly one MIN_EXAMPLE in paused responses
  - validates no runnable-hint surfaces
- `tests/regression/compute_algebraic_multistep.sh`
  - aligned with strict sequential request-set enforcement while preserving multistep checks

satisfaction of audit recommendations
- hard machine-readable STOP contract emitted at every schema boundary
- one-step schema pause semantics preserved
- no auto-chaining or auto-run signal introduced
- no continuation tokens added
