# Request

Goal:
I want to compute algebraically

Constraints:
- Keep symbolic computation deterministic.
- Keep outputs under AGENTS/tasks/<task_id>/work/.
- No USER writes during run.

Expected Deliverables:
- Generated Wolfram Language source.
- Deterministic symbolic result JSON.
- Optional figures under work/fig/.
- report.md with all required sections.

Inputs (JSON):
```json
{
  "goal": "I want to compute algebraically",
  "inputs": {
    "operation": "simplify",
    "expression": "(x^2 - 1)/(x - 1)",
    "assumptions": "x != 1",
    "solve_variable": "x",
    "plot_expression": false,
    "plot_range": [-5, 5]
  },
  "expected_outputs": {
    "result_file": "result.json"
  },
  "constraints": [
    "Use Wolfram Language only",
    "No network access"
  ],
  "preferred_formats": [
    "json",
    "png"
  ]
}
```
