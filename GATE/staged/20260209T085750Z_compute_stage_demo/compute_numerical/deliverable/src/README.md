# Numerical Compute Program

This program computes a simple affine numerical scan over a grid and records sanity checks plus stability notes.

## Run
`SPEC_PATH=AGENTS/tasks/20260209T085750Z_compute_stage_demo/work/compute/spec.yaml RESULT_PATH=AGENTS/tasks/20260209T085750Z_compute_stage_demo/outputs/compute/result.json python3 AGENTS/tasks/20260209T085750Z_compute_stage_demo/deliverable/src/main.py`

## Inputs
- `AGENTS/tasks/20260209T085750Z_compute_stage_demo/work/compute/spec.yaml`

## Outputs
- `AGENTS/tasks/20260209T085750Z_compute_stage_demo/outputs/compute/result.json`
- optional `tables/*.csv` and `fig/*` if added later

## Tolerances / stability checks
- Adjust `params.rtol` and `params.atol` in `spec.yaml`.

## Play around
- Edit `params.alpha`, `params.beta`, and `params.grid` in `spec.yaml`.
