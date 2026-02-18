# Request

Goal:
numerical compute demo

Constraints:
- Keep computation deterministic.
- Keep outputs under AGENTS/tasks/<task_id>/work/.
- No USER writes during run.

Expected Deliverables:
- Generated Python source.
- Structured numeric outputs.
- Optional figures under work/fig/.
- report.md with all required sections.

Inputs (JSON):
```json
{
  "goal": "numerical compute demo",
  "inputs": {
    "mode": "quadratic_scan",
    "x_values": [-3, -2, -1, 0, 1, 2, 3],
    "coefficients": {
      "a": 1.0,
      "b": -2.0,
      "c": 1.0
    },
    "make_plot": false
  },
  "expected_outputs": {
    "result_file": "result.json",
    "figure_file": "quadratic_scan.png"
  },
  "constraints": [
    "Use Python only",
    "No network access"
  ],
  "preferred_formats": [
    "json",
    "png"
  ]
}
```
