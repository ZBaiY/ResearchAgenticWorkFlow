# compute_multistep goal-prefill patch

## Root cause
- Repo CLI did not contain a direct goal-prefill mutator in `bart --pick/--start`; schema auto-advancement reports were driven by downstream command chaining.
- Contract gap was lack of explicit machine markers in `bart` pick/start output to anchor schema state handling at wrapper boundaries.
- Regression coverage did not explicitly assert `request.json.goal` remains empty immediately after pick/start.

## Files changed
- `bin/a`
- `tests/regression/compute_run_gate.sh`

## What changed
- `bin/a` now emits machine markers on pick/start path:
  - `SELECTED_SKILL=<skill>`
  - `TASK_NAME=<task>`
- Added regression assertions that after `bart --pick` (compute multistep):
  - output contains `REQUEST_STEP=goal`, `REQUEST_COMPLETE=false`, `STOP_REASON=need_user_input`
  - output does **not** contain `REQUEST_FIELD_UPDATED=goal`
  - `AGENTS/tasks/<TASK>/request.json` keeps `goal` empty and other schema fields unset
  - schema-flow output contains no exploration/noise tokens (`Search`, `Explored`, `rg`, `sed`, `ls`, `cat`, `--help`)
- Existing one-field-per-turn checks remain in place via request-set sequencing tests.

## Why this matches contract
- Pick/start now surfaces explicit, machine-readable schema state without mutating schema fields.
- Goal remains user-provided only via explicit `agenthub request-set --field goal ...`.
- Schema flow tests enforce no implicit field population and no exploration/noise artifacts in CLI output.

## Tests added/updated and run
- Updated: `tests/regression/compute_run_gate.sh`
- Commands run:
  - `python3 -m py_compile bin/a`
  - `tests/regression/compute_run_gate.sh`
  - `tests/regression/compute_request_completion.sh`
  - `tests/regression/compute_algebraic_multistep.sh`
- Result: all passed.
