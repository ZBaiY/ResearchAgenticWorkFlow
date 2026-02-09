# compute

Generate reproducible compute job scaffolding for a task.

## Usage

```bash
agentctl new <task_name>
agentctl run compute --task <task_id>
```

## Generated work package

Under `AGENTS/tasks/<task_id>/work/compute/`:

- `spec.yaml`
- `main.py` or `main.wl`
- `sanity_checks.md`
- `compute_report_template.md`

## Backend selection

- Default: `python`
- Override with `COMPUTE_BACKEND=wolfram`
- Or create `AGENTS/tasks/<task_id>/work/compute_backend.txt` containing `python` or `wolfram`

## Execute compute

```bash
bash AGENTS/runtime/compute_runner.sh --task <task_id>
```

Outputs are written to:

- `AGENTS/tasks/<task_id>/outputs/compute/result.json`
- `AGENTS/tasks/<task_id>/outputs/compute/hashes.json`
- `AGENTS/tasks/<task_id>/logs/compute/`
