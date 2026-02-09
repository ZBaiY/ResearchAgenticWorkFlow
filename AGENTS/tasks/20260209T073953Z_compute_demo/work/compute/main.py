#!/usr/bin/env python3
import json
import math
import os
from pathlib import Path

spec = json.loads(os.environ.get("COMPUTE_SPEC_JSON", "{}"))
params = spec.get("params", {})
a = float(params.get("a", 2.0))
b = float(params.get("b", 1.0))
xs = params.get("sample_points", [0, 1, 2, 3, 4])

ys = [a * float(x) + b for x in xs]
finite = all(math.isfinite(v) for v in ys)

payload = {
    "backend": "python",
    "computation": "linear_model",
    "inputs": {"x": xs},
    "params": {"a": a, "b": b},
    "results": {"y": ys, "mean_y": (sum(ys) / len(ys)) if ys else None},
    "sanity_checks": [
        {"name": "result_vector_length_matches_input", "passed": len(xs) == len(ys)},
        {"name": "result_values_are_finite", "passed": finite},
        {"name": "mean_value_within_expected_range", "passed": (sum(ys) / len(ys)) < 1000 if ys else False}
    ]
}

out = os.environ.get("COMPUTE_BACKEND_OUTPUT")
if not out:
    raise SystemExit("COMPUTE_BACKEND_OUTPUT is required")
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(payload, indent=2), encoding="utf-8")
