# Staged Deliverables

- task_id: 20260209T085713Z_prl_stage_demo
- skill: prl_writer
- staged_at_utc: 2026-02-09T08:57:40Z
- staged_dir: GATE/staged/20260209T085713Z_prl_stage_demo/prl_writer

## What was staged
- prl_writer/patches/patch.diff
- prl_writer/patches/files_manifest.json
- prl_writer/review/prl_writer_report.md

## Manual Promotion Commands (USER is manual-only)
- Patch-based update (if present):
    git apply GATE/staged/20260209T085713Z_prl_stage_demo/prl_writer/patches/patch.diff
- Compute source export (if present):
    cp -r GATE/staged/20260209T085713Z_prl_stage_demo/prl_writer/deliverable/src USER/src/compute/20260209T085713Z_prl_stage_demo/
- Slide export (if present):
    cp -r GATE/staged/20260209T085713Z_prl_stage_demo/prl_writer/deliverable/slides USER/presentations/20260209T085713Z_prl_stage_demo/
- Literature refs (if present):
    cp GATE/staged/20260209T085713Z_prl_stage_demo/prl_writer/review/refs.bib USER/paper/bib/20260209T085713Z_prl_stage_demo.refs.bib

## Minimal Acceptance Checklist
- Confirm report summary matches request intent.
- Inspect patch/source/result summary before promoting.
- Promote only approved files into USER manually.
