#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple

RUNTIME_DIR = Path(__file__).resolve().parents[2] / "runtime"
if str(RUNTIME_DIR) not in sys.path:
    sys.path.insert(0, str(RUNTIME_DIR))

from approval import ask_text, confirm


def now_utc() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_bool(v: str, default: bool = False) -> bool:
    if v is None:
        return default
    return str(v).strip().lower() in {"1", "true", "yes", "y", "on"}


def parse_scalar(v: str) -> Any:
    s = v.strip().strip('"').strip("'")
    if s == "":
        return ""
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    if re.fullmatch(r"-?\d+\.\d+", s):
        try:
            return float(s)
        except ValueError:
            return s
    if s.lower() in {"true", "false"}:
        return s.lower() == "true"
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        if not inner:
            return []
        return [x.strip().strip('"').strip("'") for x in inner.split(",") if x.strip()]
    return s


def extract_scalar(text: str, key: str) -> Any:
    m = re.search(rf"(?mi)^\s*{re.escape(key)}\s*:\s*(.+?)\s*$", text)
    if not m:
        return None
    return parse_scalar(m.group(1))


def extract_list_block(text: str, key: str) -> List[str]:
    lines = text.splitlines()
    out: List[str] = []
    for i, raw in enumerate(lines):
        if re.match(rf"^\s*{re.escape(key)}\s*:\s*$", raw):
            base_indent = len(raw) - len(raw.lstrip(" "))
            j = i + 1
            while j < len(lines):
                line = lines[j]
                if not line.strip():
                    j += 1
                    continue
                indent = len(line) - len(line.lstrip(" "))
                if indent <= base_indent:
                    break
                m = re.match(r"^\s*-\s+(.+?)\s*$", line)
                if m:
                    out.append(m.group(1).strip().strip('"').strip("'"))
                j += 1
            break
    return out


def load_request(req_path: Path) -> Dict[str, Any]:
    text = req_path.read_text(encoding="utf-8") if req_path.exists() else ""
    req: Dict[str, Any] = {
        "project_context": {
            "dossier_path": None,
            "paper_paths": [],
            "fig_dir": None,
        },
        "talk": {
            "title": None,
            "venue": None,
            "audience": None,
            "audience_size": None,
            "duration_min": None,
            "qna_min": None,
            "emphasis": None,
            "goal": None,
        },
        "deck": {
            "slide_count_target": None,
            "style": None,
            "constraints": [],
        },
        "export": {
            "ask_before_export": True,
            "generate_pptx": False,
            "pptx_engine": "pptxgenjs",
        },
    }

    req["project_context"]["dossier_path"] = extract_scalar(text, "dossier_path")
    req["project_context"]["fig_dir"] = extract_scalar(text, "fig_dir")
    req["project_context"]["paper_paths"] = extract_list_block(text, "paper_paths")

    for key in ["title", "venue", "audience", "audience_size", "duration_min", "qna_min", "emphasis", "goal"]:
        req["talk"][key] = extract_scalar(text, key)

    req["deck"]["slide_count_target"] = extract_scalar(text, "slide_count_target")
    req["deck"]["style"] = extract_scalar(text, "style")
    req["deck"]["constraints"] = extract_list_block(text, "constraints")

    ask_before_export = extract_scalar(text, "ask_before_export")
    generate_pptx = extract_scalar(text, "generate_pptx")
    pptx_engine = extract_scalar(text, "pptx_engine")

    if ask_before_export is not None:
        req["export"]["ask_before_export"] = bool(ask_before_export)
    if generate_pptx is not None:
        req["export"]["generate_pptx"] = bool(generate_pptx)
    if pptx_engine is not None and str(pptx_engine).strip():
        req["export"]["pptx_engine"] = str(pptx_engine).strip()

    return req


def ensure_int(v: Any, default: int) -> int:
    try:
        return int(v)
    except Exception:
        return default


def infer_slide_count(duration_min: int, requested: Any) -> int:
    if requested is not None:
        try:
            x = int(requested)
            if x > 0:
                return x
        except Exception:
            pass
    return max(8, min(30, int(round(duration_min / 1.8))))


def slugify(s: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", s.strip().lower()).strip("-")
    return slug or "slides"


def render_template(path: Path, mapping: Dict[str, str]) -> str:
    txt = path.read_text(encoding="utf-8")
    for k, v in mapping.items():
        txt = txt.replace("{{" + k + "}}", v)
    return txt


def section_plan(duration: int, slide_count: int) -> Tuple[List[Tuple[str, int]], List[Tuple[str, float]]]:
    sections = [
        ("Hook", 1),
        ("Problem", 1),
        ("Setup", 1),
        ("Method", 2),
        ("Key Results", 2),
        ("Robustness/Checks", 1),
        ("Implications", 1),
        ("Outlook", 1),
    ]
    base = sum(c for _, c in sections)
    extra = max(0, slide_count - base)
    order = ["Method", "Key Results", "Problem", "Robustness/Checks", "Implications"]
    idx = 0
    sec = dict(sections)
    while extra > 0:
        sec[order[idx % len(order)]] += 1
        extra -= 1
        idx += 1
    final_sections = [(k, sec[k]) for k, _ in sections]

    weights = {
        "Hook": 0.08,
        "Problem": 0.12,
        "Setup": 0.12,
        "Method": 0.18,
        "Key Results": 0.24,
        "Robustness/Checks": 0.10,
        "Implications": 0.08,
        "Outlook": 0.08,
    }
    raw = [(k, round(duration * weights[k], 1)) for k, _ in final_sections]
    total = sum(v for _, v in raw)
    if raw:
        adjust = round(duration - total, 1)
        last_k, last_v = raw[-1]
        raw[-1] = (last_k, round(last_v + adjust, 1))
    return final_sections, raw


def collect_figures(root: Path, fig_dir: str | None) -> List[str]:
    if not fig_dir:
        return []
    p = (root / fig_dir).resolve() if not Path(fig_dir).is_absolute() else Path(fig_dir)
    if not p.exists() or not p.is_dir():
        return []
    exts = {".pdf", ".png", ".jpg", ".jpeg", ".svg", ".eps"}
    files = [x for x in p.iterdir() if x.is_file() and x.suffix.lower() in exts]
    files = sorted(files, key=lambda x: x.name.lower())
    return [str(x.relative_to(root)) if root in x.parents else str(x) for x in files[:12]]


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def maybe_generate_pptx(task_dir: Path, logs_dir: Path, slides_outline: List[str], title: str) -> Tuple[bool, str]:
    pptx_dir = task_dir / "deliverable" / "pptx"
    pptx_dir.mkdir(parents=True, exist_ok=True)
    build_md = pptx_dir / "build.md"
    build_sh = pptx_dir / "build.sh"
    deck_path = pptx_dir / "deck.pptx"

    node = shutil.which("node")
    if node is None:
        write_text(build_md, "# PPTX build\n\nNode.js is unavailable on this machine, so deck.pptx was not generated.\n")
        return False, "node unavailable"

    check = subprocess.run([node, "-e", "require('pptxgenjs')"], capture_output=True, text=True)
    if check.returncode != 0:
        write_text(build_md, "# PPTX build\n\npptxgenjs module is not installed in the current environment.\n")
        return False, "pptxgenjs module unavailable"

    script = f"""#!/usr/bin/env bash
set -euo pipefail
node - <<'NODE'
const PptxGenJS = require('pptxgenjs');
const pptx = new PptxGenJS();
pptx.layout = 'LAYOUT_WIDE';
let s = pptx.addSlide();
s.addText({json.dumps(title)}, {{ x:0.6, y:0.6, w:12.0, h:0.8, fontSize:30, bold:true }});
s.addText('Skeleton draft generated by slide_preparation', {{ x:0.6, y:1.5, w:12.0, h:0.5, fontSize:16 }});
"""
    y = 2.2
    for i, line in enumerate(slides_outline[:10], start=1):
        safe = line.replace("'", "\\'")
        script += f"s.addText('{i}. {safe}', {{ x:0.8, y:{y:.1f}, w:11.8, h:0.35, fontSize:14 }});\n"
        y += 0.35
    script += f"""
pptx.writeFile({{ fileName: {json.dumps(str(deck_path))} }}).then(() => {{}});
NODE
"""
    write_text(build_sh, script)
    os.chmod(build_sh, 0o755)

    run = subprocess.run(["bash", str(build_sh)], capture_output=True, text=True)
    write_text(build_md, "# PPTX build\n\nGenerated with local `pptxgenjs` if available.\n")

    if run.returncode != 0 or not deck_path.exists():
        return False, "pptx build failed"
    return True, "ok"


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: run.py <repo_root> <task_id>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    task_id = sys.argv[2]
    task_dir = root / "AGENTS" / "tasks" / task_id
    req_path = task_dir / "request.md"

    if not task_dir.exists():
        print(f"Task directory missing: {task_dir}", file=sys.stderr)
        return 2
    if not req_path.exists():
        print(f"request.md missing: {req_path}", file=sys.stderr)
        return 2

    review_dir = task_dir / "review"
    logs_root = task_dir / "logs"
    logs_skill = logs_root / "slide_preparation"
    work_slides = task_dir / "work" / "slides"
    scratch_dir = work_slides / "scratch"
    build_dir = work_slides / "build"
    deliverable_slides = task_dir / "deliverable" / "slides"

    for d in [review_dir, logs_root, logs_skill, scratch_dir, build_dir]:
        d.mkdir(parents=True, exist_ok=True)

    commands: List[str] = []
    commands.append(f"read {req_path}")

    req = load_request(req_path)

    questions_asked: List[str] = []
    if not req["talk"].get("duration_min"):
        ans = ask_text("Missing talk.duration_min. Enter duration in minutes: ", "20")
        if ans:
            req["talk"]["duration_min"] = ensure_int(ans, 20)
        else:
            req["talk"]["duration_min"] = 20
        questions_asked.append("duration_min")

    if not req["talk"].get("audience"):
        ans = ask_text("Missing talk.audience. Enter expert/mixed/adjacent/general: ", "mixed")
        req["talk"]["audience"] = ans or "mixed"
        questions_asked.append("audience")

    if not req["talk"].get("venue"):
        ans = ask_text("Missing talk.venue. Enter conference/seminar/group meeting: ", "seminar")
        req["talk"]["venue"] = ans or "seminar"
        questions_asked.append("venue")

    if not req["talk"].get("emphasis") and not req["talk"].get("goal"):
        ans = ask_text("Missing emphasis/goal. Enter one short phrase for emphasis or goal: ", "")
        if ans:
            req["talk"]["emphasis"] = ans
        else:
            req["talk"]["goal"] = "status update"
        questions_asked.append("emphasis_or_goal")

    duration = ensure_int(req["talk"].get("duration_min"), 20)
    req["talk"]["duration_min"] = duration

    if not req["talk"].get("title"):
        req["talk"]["title"] = f"Talk for {task_id}"

    slide_target = infer_slide_count(duration, req["deck"].get("slide_count_target"))
    req["deck"]["slide_count_target"] = slide_target

    if not req["deck"].get("style"):
        req["deck"]["style"] = "minimal"

    constraints = req["deck"].get("constraints") or []
    if not isinstance(constraints, list):
        constraints = [str(constraints)]
        req["deck"]["constraints"] = constraints

    resolved_path = logs_skill / "resolved_request.json"
    resolved_path.write_text(json.dumps(req, indent=2), encoding="utf-8")
    commands.append(f"write {resolved_path}")

    sections, timing = section_plan(duration, slide_target)

    outline_lines: List[str] = []
    notes_lines: List[str] = []
    fig_lines: List[str] = []
    timing_lines: List[str] = []

    slide_no = 1
    for section, count in sections:
        for j in range(count):
            title = section if count == 1 else f"{section} ({j + 1}/{count})"
            outline_lines.append(f"- S{slide_no:02d}: {title}")

            notes_lines.append(f"### S{slide_no:02d}: {title}")
            notes_lines.append("- Core message: TBD in one sentence.")
            notes_lines.append("- Evidence to mention: key result/figure pointer.")
            notes_lines.append("- Transition: connect to next slide.")
            notes_lines.append("")

            fig_note = "Reuse existing figure if available."
            if section in {"Key Results", "Robustness/Checks"}:
                fig_note = "Prioritize one result figure with readable labels."
            fig_lines.append(f"- S{slide_no:02d} ({title}): {fig_note}")
            slide_no += 1

    for section, mins in timing:
        timing_lines.append(f"- {section}: {mins:.1f} min")

    if duration >= 20:
        outline_lines.append(f"- S{slide_no:02d}: Backup slides")
        notes_lines.append(f"### S{slide_no:02d}: Backup slides")
        notes_lines.append("- Include derivation details and robustness details for likely Q&A.")
        notes_lines.append("- Keep labels consistent with main deck.")
        notes_lines.append("")
        fig_lines.append(f"- S{slide_no:02d} (Backup): reserve extra plots/tables for referee-style questions.")

    fig_dir = req["project_context"].get("fig_dir")
    local_figs = collect_figures(root, fig_dir)
    if local_figs:
        fig_lines.append("")
        fig_lines.append("### Reusable local figures detected")
        for f in local_figs:
            fig_lines.append(f"- {f}")
    else:
        fig_lines.append("")
        fig_lines.append("### Reusable local figures detected")
        fig_lines.append("- none detected; mark where a new figure is needed")

    templates = root / "AGENTS" / "skills" / "slide_preparation" / "templates"
    deck_outline = render_template(
        templates / "deck_outline.md.tpl",
        {
            "talk_title": str(req["talk"].get("title") or "TBD"),
            "venue": str(req["talk"].get("venue") or "TBD"),
            "audience": str(req["talk"].get("audience") or "TBD"),
            "duration_min": str(duration),
            "slide_count_target": str(slide_target),
            "slides_block": "\n".join(outline_lines),
        },
    )
    speaker_notes = render_template(
        templates / "speaker_notes.md.tpl",
        {
            "notes_block": "\n".join(notes_lines),
        },
    )
    figure_plan = render_template(
        templates / "figure_plan.md.tpl",
        {
            "fig_dir": str(fig_dir or "not provided"),
            "constraints_summary": "; ".join(constraints) if constraints else "none",
            "figures_block": "\n".join(fig_lines),
        },
    )

    brief = [
        "# Slide Brief",
        "",
        f"- task_id: {task_id}",
        "- skill: slide_preparation",
        f"- title: {req['talk'].get('title')}",
        f"- venue: {req['talk'].get('venue')}",
        f"- audience: {req['talk'].get('audience')}",
        f"- duration_min: {duration}",
        f"- slide_count_target: {slide_target}",
        f"- style: {req['deck'].get('style')}",
        f"- emphasis: {req['talk'].get('emphasis') or 'TBD'}",
        f"- goal: {req['talk'].get('goal') or 'TBD'}",
        "",
        "## Arc",
        "Hook -> Problem -> Setup -> Method -> Key Results -> Robustness/Checks -> Implications -> Outlook",
        "",
        "## Potential blockers",
        "- Missing explicit claim hierarchy for main result slides.",
        "- Figure readability risk if labels/units are not visible from audience distance.",
        "- Time overrun risk if >1 equation per slide is used.",
        "",
        "## Clarifying questions asked",
    ]
    if questions_asked:
        for q in questions_asked:
            brief.append(f"- {q}")
    else:
        brief.append("- none")

    timing_plan = "\n".join(["# Timing Plan", "", *timing_lines])

    outputs = {
        review_dir / "slide_brief.md": "\n".join(brief) + "\n",
        review_dir / "deck_outline.md": deck_outline,
        review_dir / "speaker_notes.md": speaker_notes,
        review_dir / "figure_plan.md": figure_plan,
        review_dir / "timing_plan.md": timing_plan + "\n",
    }

    for path, content in outputs.items():
        write_text(path, content)
        commands.append(f"write {path}")

    ask_export = bool(req["export"].get("ask_before_export", True))
    export_resp = ""
    exported = False
    if ask_export:
        export_resp = "y" if confirm("Skeleton ready. Export editable slide sources into deliverable/slides/? (y/N) ", default=False) else "n"
    else:
        export_resp = "y"

    if export_resp.strip().lower() == "y":
        exported = True
        deliverable_slides.mkdir(parents=True, exist_ok=True)

        slides_md = [
            "# Slides Source",
            "",
            f"Title: {req['talk'].get('title')}",
            f"Style: {req['deck'].get('style')}",
            "",
            "## Outline",
            *outline_lines,
            "",
            "## Speaker cues",
            "- Keep each slide to one key message.",
            "- Keep equations to the minimum required by constraints.",
        ]
        assets_plan = [
            "# Assets Plan",
            "",
            f"Figure directory: {fig_dir or 'not provided'}",
            "",
            "## Reuse candidates",
        ]
        if local_figs:
            assets_plan.extend([f"- {x}" for x in local_figs])
        else:
            assets_plan.append("- none detected")
        assets_plan.extend(["", "## Additional needed assets", "- New conceptual schematic if needed for motivation slide."])

        citations = [
            "# Citations",
            "",
            "- Add primary paper citation(s) and key baseline references.",
            "- Ensure one references slide or per-slide footnote style.",
        ]

        title_slug = slugify(str(req["talk"].get("title") or task_id))
        promotion = [
            "# Promotion Instructions",
            "",
            "Agent cannot write to USER/. Run manually:",
            f"cp -r AGENTS/tasks/{task_id}/deliverable/slides USER/presentations/{title_slug}/",
            "",
            "If generated, copy pptx as needed:",
            f"cp -r AGENTS/tasks/{task_id}/deliverable/pptx USER/presentations/{title_slug}/",
        ]

        write_text(deliverable_slides / "slides.md", "\n".join(slides_md) + "\n")
        write_text(deliverable_slides / "assets_plan.md", "\n".join(assets_plan) + "\n")
        write_text(deliverable_slides / "citations.md", "\n".join(citations) + "\n")
        write_text(deliverable_slides / "promotion_instructions.md", "\n".join(promotion) + "\n")
        commands.append(f"write {deliverable_slides / 'slides.md'}")

    generated_pptx = False
    pptx_note = "not requested"
    if exported and bool(req["export"].get("generate_pptx", False)):
        generated_pptx, pptx_note = maybe_generate_pptx(
            task_dir=task_dir,
            logs_dir=logs_skill,
            slides_outline=outline_lines,
            title=str(req["talk"].get("title") or "Talk"),
        )
        commands.append("pptx_generation_attempt")

    consent = {
        "exported_source": exported,
        "user_response": export_resp.strip().lower()[:1],
        "timestamp_utc": now_utc(),
        "generate_pptx_requested": bool(req["export"].get("generate_pptx", False)),
        "generated_pptx": generated_pptx,
        "pptx_note": pptx_note,
    }
    write_text(logs_skill / "consent.json", json.dumps(consent, indent=2) + "\n")

    scratch_removed = False
    build_removed = False
    if scratch_dir.exists():
        shutil.rmtree(scratch_dir)
        scratch_removed = True
    if build_dir.exists():
        shutil.rmtree(build_dir)
        build_removed = True

    manifest = {
        "task_id": task_id,
        "skill": "slide_preparation",
        "resolved_request": req,
        "review_outputs": [str(p.relative_to(root)) for p in outputs.keys()],
        "exported": exported,
        "generated_pptx": generated_pptx,
        "cleanup": {
            "scratch_removed": scratch_removed,
            "build_removed": build_removed,
        },
    }
    write_text(logs_skill / "run_manifest.json", json.dumps(manifest, indent=2) + "\n")

    cmd_log = logs_root / "commands.txt"
    with cmd_log.open("a", encoding="utf-8") as f:
        for c in commands:
            f.write(c + "\n")

    print(f"TASK={task_id} SKILL=slide_preparation EXPORTED={str(exported).lower()} PPTX={str(generated_pptx).lower()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
