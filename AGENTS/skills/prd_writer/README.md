# prd_writer

Create a structured Product Requirements Document (PRD) from task request/context files.

## Usage

```bash
agentctl new <task_name>
agentctl run prd_writer --task <task_id>
```

## Inputs

- Required: `AGENTS/tasks/<task_id>/request.md`
- Optional:
  - `AGENTS/tasks/<task_id>/work/context.md`
  - `AGENTS/tasks/<task_id>/work/context/*.md`

## Outputs

- `AGENTS/tasks/<task_id>/deliverable/prd/PRD.md`
- `AGENTS/tasks/<task_id>/deliverable/prd/PRD.json`
- `AGENTS/tasks/<task_id>/deliverable/prd/files_manifest.json`
- `AGENTS/tasks/<task_id>/review/prd_writer_report.md`
- `AGENTS/tasks/<task_id>/logs/commands.txt`
- `AGENTS/tasks/<task_id>/logs/prd_writer.stdout.log`
- `AGENTS/tasks/<task_id>/logs/prd_writer.stderr.log`
- `AGENTS/tasks/<task_id>/logs/git_status.txt`

## Governance boundaries

- Never modify `USER/` or `GATE/`.
- Write only under `AGENTS/tasks/<task_id>/...`.
- This skill is project-contained and does not depend on globally installed skills.
