#!/usr/bin/env python3
import argparse
import datetime as dt
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def file_info(path: Path) -> Dict[str, Any]:
    if not path.exists() or not path.is_file():
        return {"path": str(path), "exists": False, "bytes": 0, "sha256": ""}
    return {
        "path": str(path),
        "exists": True,
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def load_spec(spec_path: Path) -> Dict[str, Any]:
    text = spec_path.read_text(encoding="utf-8")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Optional fallback if someone writes YAML and PyYAML exists.
        try:
            import yaml  # type: ignore

            data = yaml.safe_load(text)
            if isinstance(data, dict):
                return data
        except Exception:
            pass
        raise RuntimeError(f"Unable to parse spec: {spec_path}")


def cmd_version(cmd: List[str]) -> str:
    try:
        out = subprocess.run(cmd, check=False, capture_output=True, text=True)
        val = (out.stdout or out.stderr).strip().splitlines()
        return val[0] if val else "unknown"
    except Exception:
        return "unavailable"


def write_json(path: Path, obj: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Path to AGENTS directory")
    parser.add_argument("--task", required=True, help="task_id")
    args = parser.parse_args()

    agents_root = Path(args.root).resolve()
    task_id = args.task
    task_dir = agents_root / "tasks" / task_id
    work_compute = task_dir / "work" / "compute"
    spec_path = work_compute / "spec.yaml"
    outputs_dir = task_dir / "outputs" / "compute"
    logs_dir = task_dir / "logs" / "compute"
    commands_log = logs_dir / "commands.txt"

    if not task_dir.exists():
        print(f"Task not found: {task_dir}", file=sys.stderr)
        return 2
    if not spec_path.exists():
        print(f"Missing spec: {spec_path}", file=sys.stderr)
        return 2

    outputs_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    spec = load_spec(spec_path)
    backend = str(spec.get("backend", "python")).lower()
    entry = str(spec.get("entry", "main.py"))
    params = spec.get("params", {}) or {}

    started = now_utc()
    t0 = dt.datetime.now(dt.timezone.utc)

    versions = {
        "python": cmd_version([sys.executable, "--version"]),
        "wolframscript": cmd_version(["wolframscript", "-version"])
        if shutil.which("wolframscript")
        else "unavailable",
    }

    result_path = outputs_dir / "result.json"
    hashes_path = outputs_dir / "hashes.json"
    backend_payload_path = outputs_dir / "backend_payload.json"

    command = ""
    backend_available = True
    status = "ok"
    backend_payload: Dict[str, Any] = {}

    env = os.environ.copy()
    env["COMPUTE_SPEC_JSON"] = json.dumps(spec)
    env["COMPUTE_BACKEND_OUTPUT"] = str(backend_payload_path)

    if backend == "python":
      entry_path = work_compute / "main.py"
      command = f"python3 {entry_path}"
      commands_log.open("a", encoding="utf-8").write(command + "\n")
      if not entry_path.exists():
          status = "failed"
          backend_available = False
      else:
          proc = subprocess.run([sys.executable, str(entry_path)], env=env, capture_output=True, text=True)
          (logs_dir / "backend.stdout.log").write_text(proc.stdout or "", encoding="utf-8")
          (logs_dir / "backend.stderr.log").write_text(proc.stderr or "", encoding="utf-8")
          if proc.returncode != 0:
              status = "failed"
    elif backend == "wolfram":
      entry_path = work_compute / "main.wl"
      command = f"wolframscript -file {entry_path}"
      commands_log.open("a", encoding="utf-8").write(command + "\n")
      if not shutil.which("wolframscript"):
          backend_available = False
          status = "unavailable"
      elif not entry_path.exists():
          backend_available = False
          status = "failed"
      else:
          proc = subprocess.run(["wolframscript", "-file", str(entry_path)], env=env, capture_output=True, text=True)
          (logs_dir / "backend.stdout.log").write_text(proc.stdout or "", encoding="utf-8")
          (logs_dir / "backend.stderr.log").write_text(proc.stderr or "", encoding="utf-8")
          if proc.returncode != 0:
              status = "failed"
    else:
      backend_available = False
      status = "failed"
      commands_log.open("a", encoding="utf-8").write(f"unsupported backend: {backend}\n")

    if backend_payload_path.exists():
        try:
            backend_payload = json.loads(backend_payload_path.read_text(encoding="utf-8"))
        except Exception:
            backend_payload = {}

    inputs = []
    for item in spec.get("inputs", []):
        path = agents_root.parent / item.get("path", "")
        info = file_info(path)
        info["name"] = item.get("name", "input")
        inputs.append(info)

    results = backend_payload.get("results", {}) if isinstance(backend_payload, dict) else {}
    sanity_checks = backend_payload.get("sanity_checks", []) if isinstance(backend_payload, dict) else []
    if status == "unavailable":
        sanity_checks = [
            {
                "name": "backend_available",
                "passed": False,
                "detail": "wolframscript not installed or not on PATH",
            }
        ]

    uncertainty = {
        "method": "parameter",
        "sigma": params.get("uncertainty_sigma", None),
    }

    t1 = dt.datetime.now(dt.timezone.utc)
    duration = max((t1 - t0).total_seconds(), 0.0)

    result = {
        "meta": {
            "task_id": task_id,
            "job_name": spec.get("job_name", f"compute_{task_id}"),
            "backend": backend,
            "backend_available": backend_available,
            "status": status,
            "runner": "AGENTS/runtime/compute_runner.py",
            "started_at_utc": started,
            "finished_at_utc": now_utc(),
            "duration_seconds": duration,
            "versions": versions,
            "commands": [command] if command else [],
        },
        "inputs": inputs,
        "params": params,
        "results": results,
        "uncertainty": uncertainty,
        "sanity_checks": sanity_checks,
    }
    write_json(result_path, result)

    outputs = [file_info(result_path)]
    if backend_payload_path.exists():
        outputs.append(file_info(backend_payload_path))

    hashes = {
        "generated_at_utc": now_utc(),
        "inputs": inputs,
        "outputs": outputs,
    }
    write_json(hashes_path, hashes)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
