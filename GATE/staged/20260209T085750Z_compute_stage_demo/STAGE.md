# Staged Deliverables

- task_id: 20260209T085750Z_compute_stage_demo
- skill: compute_numerical
- staged_at_utc: 2026-02-09T08:57:54Z
- staged_dir: GATE/staged/20260209T085750Z_compute_stage_demo/compute_numerical

## What was staged
- compute_numerical/review/compute_numerical_report.md
- compute_numerical/deliverable/src
- compute_numerical/outputs/compute/result.json
- compute_numerical/logs/compute_consent.json

## Manual Promotion Commands (USER is manual-only)
- Patch-based update (if present):
    git apply GATE/staged/20260209T085750Z_compute_stage_demo/compute_numerical/patches/patch.diff
- Compute source export (if present):
    cp -r GATE/staged/20260209T085750Z_compute_stage_demo/compute_numerical/deliverable/src USER/src/compute/20260209T085750Z_compute_stage_demo/
- Slide export (if present):
    cp -r GATE/staged/20260209T085750Z_compute_stage_demo/compute_numerical/deliverable/slides USER/presentations/20260209T085750Z_compute_stage_demo/
- Literature refs (if present):
    cp GATE/staged/20260209T085750Z_compute_stage_demo/compute_numerical/review/refs.bib USER/paper/bib/20260209T085750Z_compute_stage_demo.refs.bib

## Minimal Acceptance Checklist
- Confirm report summary matches request intent.
- Inspect patch/source/result summary before promoting.
- Promote only approved files into USER manually.
