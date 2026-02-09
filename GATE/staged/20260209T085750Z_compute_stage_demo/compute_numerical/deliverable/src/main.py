#!/usr/bin/env python3
"""Numerical compute example (exported clean source).

This program evaluates an affine model over a configured grid and writes result JSON.
Edit parameters in the SPEC_PATH file to play around.
"""
import json
import math
import os
from pathlib import Path

spec = json.loads(Path(os.environ["SPEC_PATH"]).read_text(encoding="utf-8"))
params = spec["params"]
alpha = float(params["alpha"])
beta = float(params["beta"])
grid = [float(x) for x in params["grid"]]

# Core numerical model.
values = [alpha * x + beta for x in grid]
finite = all(math.isfinite(v) for v in values)

payload = {
    "meta": spec,
    "params": params,
    "results": {
        "summary": "Affine numerical scan",
        "grid": grid,
        "values": values,
        "mean": (sum(values) / len(values)) if values else None,
    },
    "sanity_checks": [
        {"name": "length_match", "pass": len(grid) == len(values), "value": len(values), "note": "grid/value lengths"},
        {"name": "finite_values", "pass": finite, "value": finite, "note": "all outputs finite"},
    ],
    "diagnostics": {
        "convergence": "not_applicable",
        "stability": {"tolerance_hint": [params.get("rtol"), params.get("atol")]},
    },
}

out = Path(os.environ.get("RESULT_PATH", "result.json"))
out.write_text(json.dumps(payload, indent=2), encoding="utf-8")
