#!/usr/bin/env python3
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple

RUNTIME_DIR = Path(__file__).resolve().parents[3] / "runtime"
if str(RUNTIME_DIR) not in sys.path:
    sys.path.insert(0, str(RUNTIME_DIR))

from approval import clarify_text


def now_utc() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def slurp(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


def tiny_yaml(text: str) -> Dict[str, Any]:
    """Very small YAML-like parser for key:value + list items used in this repo."""
    out: Dict[str, Any] = {}
    current_key = ""
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if re.match(r"^[A-Za-z0-9_\-]+:\s*", line):
            k, v = line.split(":", 1)
            k = k.strip()
            v = v.strip()
            if v == "":
                out[k] = []
                current_key = k
            elif v.startswith("[") and v.endswith("]"):
                items = [x.strip().strip("'\"") for x in v[1:-1].split(",") if x.strip()]
                out[k] = items
                current_key = ""
            elif v.lower() in {"true", "false"}:
                out[k] = v.lower() == "true"
                current_key = ""
            elif re.match(r"^-?\d+$", v):
                out[k] = int(v)
                current_key = ""
            else:
                out[k] = v.strip("'\"")
                current_key = ""
            continue
        if re.match(r"^\s*-\s+", line) and current_key:
            out.setdefault(current_key, [])
            if isinstance(out[current_key], list):
                out[current_key].append(re.sub(r"^\s*-\s+", "", line).strip().strip("'\""))
    return out


def parse_request_md(text: str) -> Dict[str, Any]:
    parsed = tiny_yaml(text)
    # Support "desired methods" alias.
    if "desired methods" in parsed and "methods" not in parsed:
        parsed["methods"] = parsed["desired methods"]
    # Normalize methods string/list.
    methods = parsed.get("methods")
    if isinstance(methods, str):
        parsed["methods"] = [m.strip() for m in methods.split(",") if m.strip()]
    return parsed


def safe_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2), encoding="utf-8")


def append_jsonl(path: Path, rows: List[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=True) + "\n")


def http_json(url: str, headers: Dict[str, str] | None = None, timeout: float = 15.0) -> Tuple[bool, Any, str]:
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read().decode("utf-8", errors="replace")
        return True, json.loads(data), ""
    except Exception as e:
        return False, None, str(e)


def http_text(url: str, headers: Dict[str, str] | None = None, timeout: float = 15.0) -> Tuple[bool, str, str]:
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read().decode("utf-8", errors="replace")
        return True, data, ""
    except Exception as e:
        return False, "", str(e)


def normalize_id(c: Dict[str, Any]) -> str:
    for k in ("arxiv_id", "doi", "id"):
        v = c.get(k)
        if v:
            return str(v).lower()
    t = c.get("title", "")
    return "title:" + re.sub(r"\s+", " ", str(t).strip().lower())[:120]


def tokenize(s: str) -> List[str]:
    return re.findall(r"[a-z0-9_+-]+", s.lower())


def score_candidate(c: Dict[str, Any], phrases: List[str]) -> float:
    blob = (str(c.get("title", "")) + " " + str(c.get("abstract", ""))).lower()
    toks = set(tokenize(blob))
    score = 0.0
    for p in phrases:
        p = p.strip().lower()
        if not p:
            continue
        if p in blob:
            score += 2.0
        for t in tokenize(p):
            if t in toks:
                score += 0.3
    return round(score, 3)


def bucket_candidate(c: Dict[str, Any], scope: Dict[str, Any]) -> str:
    text = (str(c.get("title", "")) + " " + str(c.get("abstract", ""))).lower()
    include = [x.lower() for x in scope.get("include", []) if isinstance(x, str)]
    exclude = [x.lower() for x in scope.get("exclude", []) if isinstance(x, str)]
    if include and any(k in text for k in include):
        return "direct_overlap"
    if exclude and any(k in text for k in exclude):
        return "constraint/null"
    if any(k in text for k in ["method", "algorithm", "simulation", "model", "framework"]):
        return "technique_useful"
    return "adjacent_support"


def parse_bib_seeds(text: str) -> List[str]:
    seeds: List[str] = []
    for line in text.splitlines():
        m = re.search(r"(?:arxiv[:\s]*)([A-Za-z0-9.\-/]+)", line, flags=re.I)
        if m:
            seeds.append(m.group(1))
        d = re.search(r"doi\s*=\s*\{([^}]+)\}", line, flags=re.I)
        if d:
            seeds.append(d.group(1))
    return seeds


def ask_method() -> str:
    val = clarify_text(
        "Which retrieval method to run? 1) keyword_search 2) seed_graph 3) external_search\nEnter 1/2/3: ",
        "1",
    )
    return {"1": "keyword_search", "2": "seed_graph", "3": "external_search"}.get(val, "keyword_search")


def ask_dossier_path() -> str:
    return clarify_text("dossier_path missing. Enter dossier path (e.g., USER/literature/dossiers/<project_slug>): ", "")


@dataclass
class Ctx:
    root: Path
    task_id: str
    task_dir: Path
    req_path: Path
    out_dir: Path
    review_dir: Path
    logs_dir: Path
    lit_dir: Path
    method_log: Path
    retrieval_log: List[Dict[str, Any]] = field(default_factory=list)


def keyword_search(ctx: Ctx, queries: List[str], sources: List[str], budget: Dict[str, int]) -> List[Dict[str, Any]]:
    cands: List[Dict[str, Any]] = []
    max_q = int(budget.get("max_queries", 3))
    max_hits = int(budget.get("max_hits_per_query", 20))

    for q in queries[:max_q]:
        if "arxiv" in sources:
            arxiv_q = urllib.parse.quote(q)
            url = f"https://export.arxiv.org/api/query?search_query=all:{arxiv_q}&start=0&max_results={max_hits}"
            ok, txt, err = http_text(url, headers={"User-Agent": "literature_scout/1.0"})
            ctx.retrieval_log.append({"method": "keyword_search", "source": "arxiv", "query": q, "url": url, "ok": ok, "error": err, "ts": now_utc()})
            if ok:
                try:
                    root = ET.fromstring(txt)
                    ns = {"a": "http://www.w3.org/2005/Atom"}
                    for e in root.findall("a:entry", ns):
                        title = (e.findtext("a:title", default="", namespaces=ns) or "").strip()
                        abstract = (e.findtext("a:summary", default="", namespaces=ns) or "").strip()
                        pid = (e.findtext("a:id", default="", namespaces=ns) or "").strip().split("/")[-1]
                        cands.append({"source": "arxiv", "query": q, "title": title, "abstract": abstract, "arxiv_id": pid, "url": f"https://arxiv.org/abs/{pid}"})
                except Exception as e:
                    ctx.retrieval_log.append({"method": "keyword_search", "source": "arxiv", "query": q, "ok": False, "error": f"parse_error:{e}", "ts": now_utc()})

        if "inspire" in sources:
            iq = urllib.parse.quote(q)
            url = f"https://inspirehep.net/api/literature?q={iq}&size={max_hits}"
            ok, data, err = http_json(url, headers={"Accept": "application/json"})
            ctx.retrieval_log.append({"method": "keyword_search", "source": "inspire", "query": q, "url": url, "ok": ok, "error": err, "ts": now_utc()})
            if ok and isinstance(data, dict):
                for hit in data.get("hits", {}).get("hits", [])[:max_hits]:
                    md = hit.get("metadata", {})
                    title = ""
                    if isinstance(md.get("titles"), list) and md["titles"]:
                        title = md["titles"][0].get("title", "")
                    abstract = md.get("abstracts", [{}])[0].get("value", "") if isinstance(md.get("abstracts"), list) and md.get("abstracts") else ""
                    dois = md.get("dois", [])
                    doi = dois[0].get("value", "") if isinstance(dois, list) and dois else ""
                    aid = ""
                    for i in md.get("arxiv_eprints", []) if isinstance(md.get("arxiv_eprints"), list) else []:
                        aid = i.get("value", "")
                        if aid:
                            break
                    cands.append({"source": "inspire", "query": q, "title": title, "abstract": abstract, "doi": doi, "arxiv_id": aid})

    return cands


def seed_graph(ctx: Ctx, seeds: List[str], sources: List[str], budget: Dict[str, int]) -> List[Dict[str, Any]]:
    cands: List[Dict[str, Any]] = []
    max_hits = int(budget.get("max_hits_per_query", 20))

    for seed in seeds[: int(budget.get("max_queries", 5))]:
        q = f"arxiv:{seed}" if "/" not in seed else f"doi:{seed}"
        if "inspire" in sources:
            # Endpoint interface for seed lookup and neighborhood expansion.
            lookup_url = f"https://inspirehep.net/api/literature?q={urllib.parse.quote(q)}&size=1"
            ok, data, err = http_json(lookup_url, headers={"Accept": "application/json"})
            ctx.retrieval_log.append({"method": "seed_graph", "source": "inspire", "step": "lookup_seed", "seed": seed, "url": lookup_url, "ok": ok, "error": err, "ts": now_utc()})
            if ok and isinstance(data, dict):
                for hit in data.get("hits", {}).get("hits", [])[:1]:
                    md = hit.get("metadata", {})
                    title = md.get("titles", [{}])[0].get("title", "") if isinstance(md.get("titles"), list) and md.get("titles") else ""
                    cands.append({"source": "inspire", "seed": seed, "title": title, "abstract": "", "id": str(hit.get("id", "")), "relation": "seed"})
                    pid = str(hit.get("id", ""))
                    if pid:
                        for rel, query in [("references", f"refersto:{pid}"), ("citations", f"citedby:{pid}")]:
                            rel_url = f"https://inspirehep.net/api/literature?q={urllib.parse.quote(query)}&size={max_hits}"
                            ok2, data2, err2 = http_json(rel_url, headers={"Accept": "application/json"})
                            ctx.retrieval_log.append({"method": "seed_graph", "source": "inspire", "step": rel, "seed": seed, "url": rel_url, "ok": ok2, "error": err2, "ts": now_utc()})
                            if ok2 and isinstance(data2, dict):
                                for h in data2.get("hits", {}).get("hits", [])[:max_hits]:
                                    md2 = h.get("metadata", {})
                                    t2 = md2.get("titles", [{}])[0].get("title", "") if isinstance(md2.get("titles"), list) and md2.get("titles") else ""
                                    cands.append({"source": "inspire", "seed": seed, "title": t2, "abstract": "", "id": str(h.get("id", "")), "relation": rel})

        if "semantic_scholar" in sources:
            key = os.environ.get("S2_API_KEY", "")
            if key:
                # Official API interface only; optional.
                s_url = "https://api.semanticscholar.org/recommendations/v1/papers/forpaper/" + urllib.parse.quote(seed)
                ok, data, err = http_json(s_url, headers={"x-api-key": key})
                ctx.retrieval_log.append({"method": "seed_graph", "source": "semantic_scholar", "seed": seed, "url": s_url, "ok": ok, "error": err, "ts": now_utc()})
                if ok and isinstance(data, dict):
                    for rec in data.get("recommendedPapers", [])[:max_hits]:
                        cands.append({"source": "semantic_scholar", "seed": seed, "title": rec.get("title", ""), "abstract": rec.get("abstract", ""), "doi": rec.get("externalIds", {}).get("DOI", "")})
            else:
                ctx.retrieval_log.append({"method": "seed_graph", "source": "semantic_scholar", "seed": seed, "ok": False, "error": "S2_API_KEY not set", "ts": now_utc()})

    return cands


def external_search(ctx: Ctx, dossier_dir: Path, budget: Dict[str, int]) -> List[Dict[str, Any]]:
    cands: List[Dict[str, Any]] = []
    max_total = int(budget.get("max_total_candidates", 100))
    # Interface-only ingestion from user-provided files, no scraping.
    inputs = [
        dossier_dir / "external_results.jsonl",
        dossier_dir / "external_results.json",
        ctx.task_dir / "work" / "external_results.jsonl",
        ctx.task_dir / "work" / "external_results.json",
    ]

    for p in inputs:
        if not p.exists():
            continue
        try:
            if p.suffix == ".jsonl":
                for line in p.read_text(encoding="utf-8").splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    cands.append(json.loads(line))
            else:
                data = json.loads(p.read_text(encoding="utf-8"))
                if isinstance(data, list):
                    cands.extend(data)
                elif isinstance(data, dict) and isinstance(data.get("results"), list):
                    cands.extend(data["results"])
            ctx.retrieval_log.append({"method": "external_search", "source": "user_provided", "path": str(p), "ok": True, "error": "", "ts": now_utc()})
        except Exception as e:
            ctx.retrieval_log.append({"method": "external_search", "source": "user_provided", "path": str(p), "ok": False, "error": str(e), "ts": now_utc()})

    return cands[:max_total]


def to_bib_entry(c: Dict[str, Any], idx: int) -> str:
    key = re.sub(r"[^a-zA-Z0-9]", "", (c.get("arxiv_id") or c.get("doi") or f"ref{idx}"))
    title = str(c.get("title", "Untitled")).replace("{", "").replace("}", "")
    doi = c.get("doi", "")
    arxiv_id = c.get("arxiv_id", "")
    url = c.get("url", "")
    lines = [f"@misc{{{key},", f"  title = {{{title}}},"]
    if doi:
        lines.append(f"  doi = {{{doi}}},")
    if arxiv_id:
        lines.append(f"  eprint = {{{arxiv_id}}},")
    if url:
        lines.append(f"  url = {{{url}}},")
    lines.append("}")
    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: run.py <repo_root> <task_id>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    task_id = sys.argv[2]
    task_dir = root / "AGENTS" / "tasks" / task_id

    req_path = task_dir / "request.md"
    if not task_dir.exists() or not req_path.exists():
        print("Missing task or request.md", file=sys.stderr)
        return 2

    out_dir = task_dir / "outputs" / "lit"
    review_dir = task_dir / "review"
    logs_dir = task_dir / "logs"
    skill_logs_dir = logs_dir / "literature_scout"
    out_dir.mkdir(parents=True, exist_ok=True)
    review_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)
    skill_logs_dir.mkdir(parents=True, exist_ok=True)

    ctx = Ctx(
        root=root,
        task_id=task_id,
        task_dir=task_dir,
        req_path=req_path,
        out_dir=out_dir,
        review_dir=review_dir,
        logs_dir=logs_dir,
        lit_dir=out_dir,
        method_log=logs_dir / "method.json",
    )

    req = parse_request_md(slurp(req_path))
    dossier = str(req.get("dossier_path", "")).strip()
    if not dossier:
        dossier = ask_dossier_path()
    dossier_dir = root / dossier if dossier else Path("")

    methods = req.get("methods", [])
    if isinstance(methods, str):
        methods = [methods]
    methods = [m.strip() for m in methods if m and m.strip()]

    method_selected_interactively = False
    method_selection_mode = "provided"
    if not methods:
        selected = ask_method()
        methods = [selected]
        mode_env = os.environ.get("APPROVAL_MODE", "interactive").strip().lower()
        interactive_env = os.environ.get("APPROVAL_INTERACTIVE", "")
        method_selected_interactively = bool(mode_env == "interactive" and interactive_env == "1")
        method_selection_mode = "interactive" if method_selected_interactively else "draft_default"
        safe_json(
            ctx.method_log,
            {
                "selected_interactively": method_selected_interactively,
                "selection_mode": method_selection_mode,
                "method": selected,
                "timestamp_utc": now_utc(),
            },
        )
    else:
        safe_json(
            ctx.method_log,
            {
                "selected_interactively": False,
                "selection_mode": method_selection_mode,
                "method": methods[0],
                "methods": methods,
                "timestamp_utc": now_utc(),
            },
        )

    safe_json(
        skill_logs_dir / "resolved_request.json",
        {
            "task_id": task_id,
            "dossier_path": dossier,
            "methods": methods,
            "method_selected_interactively": method_selected_interactively,
            "method_selection_mode": method_selection_mode,
            "timestamp_utc": now_utc(),
        },
    )

    budget = req.get("budget", {}) if isinstance(req.get("budget"), dict) else {}
    if not budget:
        budget = {"max_queries": 3, "max_hits_per_query": 20, "max_total_candidates": 100}

    sources = req.get("sources", ["arxiv", "inspire"])
    if isinstance(sources, str):
        sources = [s.strip() for s in sources.split(",") if s.strip()]

    scope = tiny_yaml(slurp(dossier_dir / "scope.yaml")) if dossier_dir else {}
    queries_cfg = tiny_yaml(slurp(dossier_dir / "queries.yaml")) if dossier_dir else {}
    queries = []
    if isinstance(queries_cfg.get("queries"), list):
        queries.extend([q for q in queries_cfg.get("queries", []) if isinstance(q, str)])
    # Fallback from request text snippets if no query list.
    if not queries:
        req_text = slurp(req_path)
        for line in req_text.splitlines():
            if line.lower().startswith("query:"):
                queries.append(line.split(":", 1)[1].strip())
    if not queries:
        queries = [scope.get("topic", "general topic")]

    seeds = []
    seeds_bib = slurp(dossier_dir / "seeds.bib") if dossier_dir else ""
    if seeds_bib:
        seeds.extend(parse_bib_seeds(seeds_bib))
    if isinstance(req.get("seeds"), list):
        seeds.extend([s for s in req["seeds"] if isinstance(s, str)])

    safe_json(out_dir / "query_plan.json", {
        "task_id": task_id,
        "timestamp_utc": now_utc(),
        "methods": methods,
        "queries": [{"query": q, "sources": sources} for q in queries[: int(budget.get("max_queries", 3))]],
        "seeds": seeds,
        "budget": budget,
        "dossier_path": dossier,
    })

    candidates: List[Dict[str, Any]] = []
    for m in methods:
        if m == "keyword_search":
            candidates.extend(keyword_search(ctx, queries, sources, budget))
        elif m == "seed_graph":
            candidates.extend(seed_graph(ctx, seeds, sources, budget))
        elif m == "external_search":
            candidates.extend(external_search(ctx, dossier_dir, budget))
        else:
            ctx.retrieval_log.append({"method": m, "ok": False, "error": "unsupported method", "ts": now_utc()})

    # Dedup and score.
    seen = set()
    deduped = []
    phrases = list(queries)
    include = scope.get("include", []) if isinstance(scope.get("include"), list) else []
    phrases.extend([x for x in include if isinstance(x, str)])

    max_total = int(budget.get("max_total_candidates", 100))
    for c in candidates:
        key = normalize_id(c)
        if key in seen:
            continue
        seen.add(key)
        c["_score"] = score_candidate(c, phrases)
        c["bucket"] = bucket_candidate(c, scope)
        deduped.append(c)
        if len(deduped) >= max_total:
            break

    deduped.sort(key=lambda x: float(x.get("_score", 0.0)), reverse=True)
    append_jsonl(out_dir / "raw_candidates.jsonl", deduped)
    safe_json(out_dir / "retrieval_log.json", ctx.retrieval_log)

    buckets = {
        "direct_overlap": [],
        "adjacent_support": [],
        "constraint/null": [],
        "technique_useful": [],
    }
    for c in deduped:
        buckets.setdefault(c.get("bucket", "adjacent_support"), []).append(c)

    topn = 8
    report_lines = [
        "# Literature Scout Report",
        "",
        f"- task_id: {task_id}",
        f"- methods: {', '.join(methods)}",
        f"- dossier_path: {dossier or 'TBD'}",
        f"- timestamp_utc: {now_utc()}",
        "",
        "## Retrieval summary",
        f"- candidates_total: {len(candidates)}",
        f"- deduped_total: {len(deduped)}",
        f"- sources: {', '.join(sources)}",
        "",
    ]

    for bname in ["direct_overlap", "adjacent_support", "constraint/null", "technique_useful"]:
        report_lines.append(f"## Bucket: {bname}")
        items = buckets.get(bname, [])[:topn]
        if not items:
            report_lines.append("- (none)")
            report_lines.append("")
            continue
        for c in items:
            title = c.get("title", "Untitled")
            src = c.get("source", "unknown")
            score = c.get("_score", 0)
            note = "Relevant by phrase overlap and source match."
            report_lines.append(f"- **{title}** [{src}] score={score}: {note}")
        report_lines.append("")

    (review_dir / "literature_scout_report.md").write_text("\n".join(report_lines), encoding="utf-8")

    risk_lines = [
        "# Referee Risk Memo",
        "",
        "Potential papers a referee may cite against the current framing:",
        "",
    ]
    risk_pool = buckets.get("constraint/null", [])[:8] or buckets.get("adjacent_support", [])[:8]
    if not risk_pool:
        risk_lines.append("- TBD: no explicit contradictory papers identified in current retrieval set.")
    for c in risk_pool:
        risk_lines.append(f"- {c.get('title', 'Untitled')} ({c.get('source', 'unknown')}): explain boundary conditions and contrast explicitly.")
    (review_dir / "referee_risk.md").write_text("\n".join(risk_lines), encoding="utf-8")

    bib_entries = [to_bib_entry(c, i + 1) for i, c in enumerate(deduped[: min(30, len(deduped))])]
    if not bib_entries:
        bib_entries = ["% No curated references yet. Expand query scope or provide seeds."]
    (review_dir / "refs.bib").write_text("\n\n".join(bib_entries) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
