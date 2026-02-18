# compute_multistep constraints example patch

## File touched
- `bin/agenthub:227`
- `bin/agenthub:546`
- `bin/agenthub:898`
- `tests/regression/compute_algebraic_multistep.sh:7`
- `tests/regression/compute_algebraic_multistep.sh:78`

## Change
- Added a multistep-specific `constraints` `MIN_EXAMPLE` string:
  - `assumptions: a>0, x in Reals; limits: time<10s; tools: local symbolic only; network: none`
- Scoped this example to `compute_algebraic_multistep` only via `schema_example_line(step, skill)`.
- Added regression assertion that this exact `MIN_EXAMPLE` appears in the constraints step output and not in goal/inputs/expected_outputs steps.

## Test command
- `tests/regression/compute_algebraic_multistep.sh`
