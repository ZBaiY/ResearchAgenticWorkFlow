#!/usr/bin/env python3
import argparse
import json
import math
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

LATEX_STOPWORDS = {
    "begin", "end", "newcommand", "section", "subsection", "ref", "eq", "fig", "table",
    "appendix", "documentclass", "usepackage", "label", "cite", "item", "textbf", "textit",
    "equation", "align", "mathbf", "mathrm", "left", "right", "theta", "omega",
}

META_FIELD_STOPWORDS = {
    "abstract", "arxiv", "authors", "author", "title", "doi", "journal", "year",
    "keywords", "channels", "datasets", "dataset", "manuscript", "preprint",
    "references", "ref", "bibliography", "bibtex", "tex", "latex",
    "supplement", "appendix", "figure", "table", "equation",
}
DEMO_STOPWORDS = {"test", "autopilot", "placeholder", "dummy", "example", "sample"}

STOPWORDS = {
    "the", "and", "for", "with", "this", "that", "from", "into", "their", "there", "where", "while",
    "about", "above", "after", "again", "against", "below", "between", "both", "could", "should",
    "would", "cannot", "under", "over", "such", "than", "then", "them", "they", "were", "have",
    "has", "had", "been", "being", "also", "using", "used", "our", "your", "you", "his", "her",
    "its", "these", "those", "which", "when", "what", "whose", "within", "without", "during",
    "because", "therefore", "however", "thus", "via", "per", "can", "may", "might", "must", "will",
    "shall", "not", "are", "was", "is", "be", "a", "an", "of", "to", "in", "on", "by", "as",
    "we", "it", "or", "at", "if", "do", "did", "done", "very", "more", "most", "least",
    "paper", "study", "result", "results", "analysis", "model", "models", "method", "methods",
    "introduction", "conclusion", "related", "work", "works", "data", "figure", "figures",
}
STOPWORDS |= LATEX_STOPWORDS | META_FIELD_STOPWORDS | DEMO_STOPWORDS

DF_RATIO_MAX = 0.85
DF_MIN = 1
TOP_K_KEYWORDS = 30
TOP_K_BIGRAMS = 20
TOP_K_TRIGRAMS = 15
SEED_TOP_K = 5
MIN_KEYWORDS = 12
MIN_COMPLETE_SEEDS = 3
MIN_KEYWORD_PHRASES = 3
MIN_DOMAIN_TOKENS = 8
MAX_FIELDNAME_KEYWORD_RATIO = 0.05
MAX_INCLUDE_DEPTH = 20
TOKEN_RE = re.compile(r"[a-zA-Z][a-zA-Z0-9_+\-]{2,}")
URL_RE = re.compile(r"^https?://", re.I)
ARXIV_ID_RE = re.compile(r"(?:arxiv:)?\s*(\d{4}\.\d{4,5}(?:v\d+)?)", re.I)
DOI_RE = re.compile(r"\b10\.\d{4,9}/[-._;()/:A-Za-z0-9]+")
YEAR_RE = re.compile(r"\b(19\d{2}|20\d{2})\b")
TEX_CONTROL_WORDS = {
    "begin", "end", "newcommand", "equation", "cite", "ref", "label", "section",
    "subsection", "documentclass", "usepackage",
}
REF_FIELDNAME_TOKENS = {
    "title", "authors", "author", "arxiv", "abstract", "doi", "year", "keywords",
    "journal", "note", "comment",
}


@dataclass
class BibEntry:
    bibkey: str
    entry_type: str
    fields: Dict[str, str]
    source_path: str


@dataclass
class RefCandidate:
    source_path: str
    title: str
    authors: List[str]
    year: str
    arxiv_id: str
    doi: str
    abstract: str
    link: str
    text: str
    capitalized_tokens: List[str]
    extraction_evidence: Dict[str, object] = field(default_factory=dict)


def now_utc() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def slurp(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore") if path.exists() else ""


def strip_comments(text: str) -> str:
    return re.sub(r"(?<!\\)%.*", "", text)


def clean_latex_text(text: str) -> str:
    t = strip_comments(text)
    t = re.sub(r"\\newcommand\s*\{[^}]*\}\s*(\[[^\]]*\])?\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}", " ", t, flags=re.S)
    t = re.sub(r"\\\[[\s\S]*?\\\]", " ", t)
    t = re.sub(r"\\\([\s\S]*?\\\)", " ", t)
    t = re.sub(r"\$\$[\s\S]*?\$\$", " ", t)
    t = re.sub(r"\$[^$]*\$", " ", t)
    t = re.sub(r"\\begin\{[^}]+\}[\s\S]*?\\end\{[^}]+\}", " ", t)
    t = re.sub(r"\\[a-zA-Z@]+\*?(?:\[[^\]]*\])?\{([^{}]*)\}", r" \1 ", t)
    t = re.sub(r"\\[a-zA-Z@]+\*?(?:\[[^\]]*\])?", " ", t)
    t = re.sub(r"[{}~^\\]", " ", t)
    t = re.sub(r"[^\w\s+\-]", " ", t)
    t = re.sub(r"\s+", " ", t)
    return t.strip()


def normalize_text(text: str) -> str:
    t = re.sub(r"[^\w\s+\-]", " ", text)
    t = re.sub(r"\s+", " ", t)
    return t.strip()


def tokenize(text: str) -> List[str]:
    toks = [m.group(0).lower() for m in TOKEN_RE.finditer(text)]
    return [t for t in toks if t not in STOPWORDS]


def choose_main_tex(tex_files: List[Path]) -> Path:
    names = {p.name: p for p in tex_files}
    if "main.tex" in names:
        return names["main.tex"]
    for p in tex_files:
        txt = slurp(p)
        if re.search(r"\\documentclass|\\begin\{document\}", txt):
            return p
    return sorted(tex_files)[0]


def resolve_include(base: Path, ref: str) -> Path:
    ref = ref.strip().strip('"').strip("'")
    p = (base.parent / ref)
    if p.suffix == "":
        p = p.with_suffix(".tex")
    return p.resolve()


def expand_tex_graph(main_tex: Path) -> List[Path]:
    visited: Set[Path] = set()
    ordered: List[Path] = []

    def walk(p: Path, depth: int) -> None:
        if depth > MAX_INCLUDE_DEPTH:
            return
        rp = p.resolve()
        if rp in visited or not rp.exists() or rp.suffix.lower() != ".tex":
            return
        visited.add(rp)
        ordered.append(rp)
        txt = strip_comments(slurp(rp))
        for m in re.finditer(r"\\(?:input|include)\{([^}]+)\}", txt):
            walk(resolve_include(rp, m.group(1)), depth + 1)

    walk(main_tex.resolve(), 0)
    return ordered


def discover_bib_files(tex_files: List[Path], paper_root: Path) -> List[Path]:
    found: List[Path] = []
    for tex in tex_files:
        txt = strip_comments(slurp(tex))
        for m in re.finditer(r"\\bibliography\{([^}]+)\}", txt):
            for raw in m.group(1).split(","):
                raw = raw.strip()
                if not raw:
                    continue
                b = (tex.parent / raw)
                if b.suffix == "":
                    b = b.with_suffix(".bib")
                if b.exists():
                    found.append(b.resolve())
        for m in re.finditer(r"\\addbibresource\{([^}]+)\}", txt):
            raw = m.group(1).strip()
            if not raw:
                continue
            b = (tex.parent / raw)
            if b.suffix == "":
                b = b.with_suffix(".bib")
            if b.exists():
                found.append(b.resolve())
    if not found:
        found = sorted([p.resolve() for p in paper_root.rglob("*.bib") if p.is_file()])

    out: List[Path] = []
    seen: Set[Path] = set()
    for p in found:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def collect_cite_keys(tex_files: List[Path]) -> List[str]:
    keys: List[str] = []
    for tex in tex_files:
        txt = strip_comments(slurp(tex))
        for m in re.finditer(r"\\cite[a-zA-Z*]*\s*(?:\[[^\]]*\]\s*)*\{([^}]+)\}", txt):
            for k in m.group(1).split(","):
                k = k.strip()
                if k:
                    keys.append(k)
    out: List[str] = []
    seen: Set[str] = set()
    for k in keys:
        if k not in seen:
            seen.add(k)
            out.append(k)
    return out


def extract_structured_phrases(tex_files: List[Path]) -> List[str]:
    items: List[str] = []
    for tex in tex_files:
        txt = strip_comments(slurp(tex))
        for m in re.finditer(r"\\keywords\{([^}]+)\}", txt, flags=re.I):
            for part in re.split(r"[,;]", m.group(1)):
                part = clean_latex_text(part).strip().lower()
                if part and part not in items:
                    items.append(part)
    return items


def extract_blocks(main_text: str) -> Dict[str, str]:
    text = strip_comments(main_text)
    title = ""
    abstract = ""
    intro = ""

    mt = re.search(r"\\title\{([\s\S]*?)\}", text)
    if mt:
        title = clean_latex_text(mt.group(1))

    ma = re.search(r"\\begin\{abstract\}([\s\S]*?)\\end\{abstract\}", text, flags=re.I)
    if ma:
        abstract = clean_latex_text(ma.group(1))

    mi = re.search(r"\\section\*?\{\s*introduction\s*\}([\s\S]*?)(?:\\section\*?\{|\\end\{document\}|$)", text, flags=re.I)
    if mi:
        intro = clean_latex_text(mi.group(1))

    return {"title": title, "abstract": abstract, "introduction": intro}


def parse_bib_entries(text: str, source_path: str) -> List[BibEntry]:
    entries: List[BibEntry] = []
    i = 0
    n = len(text)
    while i < n:
        at = text.find("@", i)
        if at == -1:
            break
        m = re.match(r"@\s*([A-Za-z]+)\s*\{", text[at:])
        if not m:
            i = at + 1
            continue
        entry_type = m.group(1).lower()
        start = at + m.end()
        depth = 1
        j = start
        while j < n and depth > 0:
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
            j += 1
        body = text[start:j - 1].strip()
        i = j
        if "," not in body:
            continue
        key, fields_blob = body.split(",", 1)
        bibkey = key.strip()
        fields: Dict[str, str] = {}
        for fm in re.finditer(r"([A-Za-z][A-Za-z0-9_\-]*)\s*=\s*(\{(?:[^{}]|\{[^{}]*\})*\}|\"(?:[^\"\\]|\\.)*\"|[^,]+)", fields_blob, flags=re.S):
            k = fm.group(1).lower()
            raw = fm.group(2).strip().strip(",")
            if raw.startswith("{") and raw.endswith("}"):
                raw = raw[1:-1]
            elif raw.startswith('"') and raw.endswith('"'):
                raw = raw[1:-1]
            fields[k] = re.sub(r"\s+", " ", clean_latex_text(raw)).strip()
        entries.append(BibEntry(bibkey=bibkey, entry_type=entry_type, fields=fields, source_path=source_path))
    return entries


def parse_authors(raw: str) -> List[str]:
    raw = raw.strip()
    if not raw:
        return []
    parts = [x.strip() for x in re.split(r"\band\b|,", raw) if x.strip()]
    return parts if parts else []


def parse_metadata_from_text(text: str) -> Dict[str, object]:
    lines = [x.strip() for x in text.splitlines() if x.strip()]
    title = lines[0] if lines else ""
    m_abs = re.search(r"\babstract\b[:\s\-]*(.+?)(?:\n\n|\n[A-Z][A-Za-z ]{1,40}:|$)", text, flags=re.I | re.S)
    abstract = normalize_text(m_abs.group(1)) if m_abs else ""
    m_doi = DOI_RE.search(text)
    m_arxiv = ARXIV_ID_RE.search(text)
    m_year = YEAR_RE.search(text)

    authors: List[str] = []
    for pat in [r"^authors?\s*:\s*(.+)$", r"^by\s+(.+)$"]:
        m = re.search(pat, text, flags=re.I | re.M)
        if m:
            authors = parse_authors(m.group(1))
            if authors:
                break
    if not authors and len(lines) > 1:
        maybe = lines[1]
        if len(maybe.split()) <= 12 and not YEAR_RE.search(maybe):
            authors = parse_authors(maybe)

    arxiv_id = m_arxiv.group(1) if m_arxiv else ""
    doi = m_doi.group(0) if m_doi else ""
    link = ""
    if arxiv_id:
        link = f"https://arxiv.org/abs/{arxiv_id}"
    elif doi:
        link = f"https://doi.org/{doi}"
    return {
        "title": normalize_text(title),
        "authors": authors,
        "year": int(m_year.group(1)) if m_year else None,
        "arxiv_id": arxiv_id or None,
        "doi": doi or None,
        "abstract": abstract,
        "link": link,
    }


PDF_PROSE_REJECT_TERMS = {
    "neutrino",
    "dark",
    "matter",
    "implications",
    "oscillations",
    "oscillation",
    "experiment",
    "scenario",
    "juno",
    "kamland",
    "resonance",
    "phenomenology",
}
AFFILIATION_HINTS = {
    "university",
    "institute",
    "department",
    "laboratory",
    "school",
    "center",
    "centre",
    "college",
    "email",
    "corresponding",
}


def _name_like_token(tok: str) -> bool:
    t = tok.strip(" ,.;:-")
    if not t:
        return False
    if re.fullmatch(r"[A-Z]\.?", t):
        return True
    if re.fullmatch(r"[A-Z][a-z]+(?:-[A-Z]?[a-z]+)?", t):
        return True
    return False


def is_author_line(line: str) -> bool:
    s = line.strip()
    if not s:
        return False
    s_l = s.lower()
    if any(x in s_l for x in ["http://", "https://", "@"]):
        return False
    if any(t in s_l for t in PDF_PROSE_REJECT_TERMS):
        return False
    if any(t in s_l for t in AFFILIATION_HINTS):
        return False
    if s.endswith((':', ';', '-')):
        return False

    toks = [t for t in re.findall(r"[A-Za-z][A-Za-z.\-']*", s) if t]
    if len(toks) < 2:
        return False
    lower_ratio = len([t for t in toks if t[0].islower()]) / max(1, len(toks))
    if lower_ratio > 0.35:
        return False
    stop_hits = len([t for t in toks if t.lower() in STOPWORDS])
    if stop_hits > max(1, len(toks) // 3):
        return False

    name_like = sum(1 for t in toks if _name_like_token(t))
    has_author_separators = ("," in s) or bool(re.search(r"\band\b|\bet al\.?\b", s_l))
    if name_like >= 2 and (has_author_separators or len(toks) <= 10):
        return True
    return False


def parse_pdf_first_page_metadata(text: str) -> Tuple[Dict[str, object], Dict[str, object]]:
    lines = [x.strip() for x in text.splitlines() if x.strip()]
    lines = [x for x in lines if not re.fullmatch(r"\d+", x)]
    evidence: Dict[str, object] = {"title_lines": [], "author_lines": [], "method": "pdf_first_page_rules"}
    if not lines:
        return parse_metadata_from_text(text), evidence

    title_lines: List[str] = [lines[0]]
    author_lines: List[str] = []
    idx = 1
    while idx < len(lines):
        ln = lines[idx]
        ln_l = ln.lower()
        if re.match(r"^abstract\b", ln_l):
            break
        if any(h in ln_l for h in AFFILIATION_HINTS) or "@" in ln:
            break
        if is_author_line(ln):
            author_lines.append(ln)
            idx += 1
            while idx < len(lines) and len(author_lines) < 3 and is_author_line(lines[idx]):
                author_lines.append(lines[idx])
                idx += 1
            break
        if len(title_lines) < 3:
            title_lines.append(ln)
            idx += 1
            continue
        break

    title_joined = normalize_text(" ".join(title_lines))
    parsed = parse_metadata_from_text(text)
    parsed["title"] = title_joined or parsed.get("title", "")

    authors: List[str] = []
    for ln in author_lines:
        for seg in parse_authors(ln):
            seg_clean = re.sub(r"\s+", " ", seg).strip()
            if not seg_clean:
                continue
            if any(t in seg_clean.lower() for t in PDF_PROSE_REJECT_TERMS):
                continue
            name_toks = [t for t in re.findall(r"[A-Za-z][A-Za-z.\-']*", seg_clean) if t]
            if sum(1 for t in name_toks if _name_like_token(t)) >= 2:
                authors.append(seg_clean)
    parsed["authors"] = dedup_keep_order(authors)

    evidence["title_lines"] = title_lines[:3]
    evidence["author_lines"] = author_lines[:3]
    return parsed, evidence


def parse_structured_text_fields(text: str) -> Tuple[bool, Dict[str, str]]:
    kv_lines = 0
    fields: Dict[str, str] = {}
    for raw in text.splitlines():
        m = re.match(r"^\s*([A-Za-z][A-Za-z0-9_\- ]{0,40})\s*:\s*(.+?)\s*$", raw)
        if not m:
            continue
        kv_lines += 1
        key = m.group(1).strip().lower().replace("-", "_").replace(" ", "_")
        val = m.group(2).strip()
        if key in {"title", "abstract", "keywords", "note", "comment", "authors", "author", "doi", "arxiv", "year"}:
            prev = fields.get(key, "")
            fields[key] = f"{prev} {val}".strip() if prev else val
    # Structured if multiple key:value lines and at least one semantic field.
    return kv_lines >= 2 and len(fields) > 0, fields


def semantic_text_from_structured_fields(fields: Dict[str, str]) -> str:
    vals: List[str] = []
    for k in ["title", "abstract", "keywords", "note", "comment"]:
        v = fields.get(k, "").strip()
        if v:
            vals.append(v)
    return "\n".join(vals)


def capitalized_tokens(text: str) -> Set[str]:
    # Drop TitleCase-like tokens from references where original casing exists.
    toks = re.findall(r"\b[A-Z][a-z]{2,}\b", text)
    return {t.lower() for t in toks}


def author_name_tokens_from_authors(authors: List[str]) -> Set[str]:
    out: Set[str] = set()
    for a in authors:
        for tok in re.findall(r"[A-Za-z]{3,}", a):
            out.add(tok.lower())
    return out


def read_pdf_text(pdf_path: Path) -> str:
    cp = subprocess.run(["pdftotext", "-f", "1", "-l", "2", str(pdf_path), "-"], text=True, capture_output=True)
    if cp.returncode == 0 and cp.stdout.strip():
        return cp.stdout
    # lightweight fallback: try plain extraction from raw bytes (no OCR)
    data = pdf_path.read_bytes()
    raw = data.decode("latin1", errors="ignore")
    candidates = re.findall(r"\(([^\)]{8,})\)", raw)
    if candidates:
        return "\n".join(candidates)
    # allow plain-text surrogates with .pdf extension in local fixtures.
    if "abstract" in raw.lower() or len(raw.strip()) > 40:
        return raw
    return ""


def discover_notes(note_root: Path) -> List[Path]:
    exts = {".md", ".tex", ".txt"}
    if not note_root.exists():
        return []
    return sorted([p.resolve() for p in note_root.rglob("*") if p.is_file() and p.suffix.lower() in exts])


def discover_note_reference_candidates(note_files: List[Path]) -> List[RefCandidate]:
    out: List[RefCandidate] = []
    for p in note_files:
        txt = slurp(p)
        if not txt.strip():
            continue
        arx_ids = [normalize_arxiv_id(m.group(1)) for m in ARXIV_ID_RE.finditer(txt)]
        dois = [m.group(0).strip() for m in DOI_RE.finditer(txt)]
        if not arx_ids and not dois:
            continue
        title = ""
        for line in txt.splitlines():
            s = line.strip()
            if s and len(s.split()) >= 3:
                title = normalize_text(s)
                break
        if not title:
            title = p.stem
        out.append(
            RefCandidate(
                source_path=str(p),
                title=title,
                authors=[],
                year="",
                arxiv_id=arx_ids[0] if arx_ids else "",
                doi=dois[0] if dois else "",
                abstract="",
                link=f"https://arxiv.org/abs/{arx_ids[0]}" if arx_ids else (f"https://doi.org/{dois[0]}" if dois else ""),
                text=normalize_text(txt),
                capitalized_tokens=sorted(capitalized_tokens(txt)),
            )
        )
    return out


def discover_reference_candidates(ref_root: Path, warnings: List[str], label: str = "USER/references/for_seeds") -> List[RefCandidate]:
    if not ref_root.exists():
        warnings.append(f"No {label}/ directory or no files found")
        return []

    files = sorted([p for p in ref_root.rglob("*") if p.is_file()])
    ref_files = [p for p in files if p.suffix.lower() in {".pdf", ".txt", ".md", ".json"}]
    if not ref_files:
        warnings.append(f"No reference files (.pdf/.txt/.md/.json) found under {label}/")
        return []

    out: List[RefCandidate] = []
    for p in ref_files:
        suffix = p.suffix.lower()
        meta: Dict[str, object] = {}
        blob = ""
        cap_tokens: Set[str] = set()
        evidence: Dict[str, object] = {}

        try:
            if suffix == ".json":
                obj = json.loads(slurp(p))
                # Structured: only semantic values, never field names.
                semantic_vals: List[str] = []
                for k in ["title", "abstract", "keywords", "note", "comment"]:
                    if obj.get(k):
                        semantic_vals.append(str(obj.get(k)))
                blob = "\n".join(semantic_vals)
                parsed = parse_metadata_from_text(blob)
                parsed["title"] = str(obj.get("title", parsed["title"]))
                parsed["abstract"] = str(obj.get("abstract", parsed["abstract"]))
                if obj.get("doi"):
                    parsed["doi"] = str(obj.get("doi"))
                if obj.get("arxiv"):
                    parsed["arxiv_id"] = str(obj.get("arxiv"))
                    parsed["link"] = f"https://arxiv.org/abs/{parsed['arxiv_id']}"
                if obj.get("authors") and not parsed.get("authors"):
                    if isinstance(obj.get("authors"), list):
                        parsed["authors"] = [str(x) for x in obj.get("authors") if str(x).strip()]
                    else:
                        parsed["authors"] = parse_authors(str(obj.get("authors")))
                if obj.get("year"):
                    try:
                        parsed["year"] = int(obj.get("year"))
                    except Exception:
                        pass
                meta = parsed
                cap_tokens |= capitalized_tokens(blob)
            elif suffix in {".txt", ".md"}:
                raw = slurp(p)
                is_structured, fields = parse_structured_text_fields(raw)
                if is_structured:
                    semantic_blob = semantic_text_from_structured_fields(fields)
                    blob = semantic_blob if semantic_blob.strip() else raw
                    meta = parse_metadata_from_text(blob)
                    if fields.get("title"):
                        meta["title"] = normalize_text(fields.get("title", ""))
                    if fields.get("abstract"):
                        meta["abstract"] = normalize_text(fields.get("abstract", ""))
                    authors_src = fields.get("authors") or fields.get("author") or ""
                    if authors_src and not meta.get("authors"):
                        meta["authors"] = parse_authors(authors_src)
                    if fields.get("doi"):
                        meta["doi"] = fields.get("doi")
                    if fields.get("arxiv"):
                        marx = ARXIV_ID_RE.search(fields.get("arxiv", ""))
                        if marx:
                            meta["arxiv_id"] = marx.group(1)
                            meta["link"] = f"https://arxiv.org/abs/{marx.group(1)}"
                    if fields.get("year"):
                        my = YEAR_RE.search(fields.get("year", ""))
                        if my:
                            meta["year"] = int(my.group(1))
                else:
                    blob = raw
                    meta = parse_metadata_from_text(blob)
                cap_tokens |= capitalized_tokens(raw)
            elif suffix == ".pdf":
                sidecar = None
                for ext in [".json", ".md", ".txt"]:
                    sp = p.with_suffix(ext)
                    if sp.exists():
                        sidecar = sp
                        break
                if sidecar is not None:
                    if sidecar.suffix.lower() == ".json":
                        obj = json.loads(slurp(sidecar))
                        semantic_vals: List[str] = []
                        for k in ["title", "abstract", "keywords", "note", "comment"]:
                            if obj.get(k):
                                semantic_vals.append(str(obj.get(k)))
                        blob = "\n".join(semantic_vals)
                        meta = parse_metadata_from_text(blob)
                        if obj.get("title"):
                            meta["title"] = str(obj.get("title"))
                        if obj.get("abstract"):
                            meta["abstract"] = str(obj.get("abstract"))
                        if obj.get("doi"):
                            meta["doi"] = str(obj.get("doi"))
                        if obj.get("arxiv"):
                            meta["arxiv_id"] = str(obj.get("arxiv"))
                            meta["link"] = f"https://arxiv.org/abs/{meta['arxiv_id']}"
                        if obj.get("authors") and not meta.get("authors"):
                            if isinstance(obj.get("authors"), list):
                                meta["authors"] = [str(x) for x in obj.get("authors") if str(x).strip()]
                            else:
                                meta["authors"] = parse_authors(str(obj.get("authors")))
                        if obj.get("year"):
                            try:
                                meta["year"] = int(obj.get("year"))
                            except Exception:
                                pass
                        cap_tokens |= capitalized_tokens(blob)
                    else:
                        raw_side = slurp(sidecar)
                        is_structured, fields = parse_structured_text_fields(raw_side)
                        if is_structured:
                            semantic_blob = semantic_text_from_structured_fields(fields)
                            blob = semantic_blob if semantic_blob.strip() else raw_side
                            meta = parse_metadata_from_text(blob)
                            if fields.get("title"):
                                meta["title"] = normalize_text(fields.get("title", ""))
                            if fields.get("abstract"):
                                meta["abstract"] = normalize_text(fields.get("abstract", ""))
                            authors_src = fields.get("authors") or fields.get("author") or ""
                            if authors_src and not meta.get("authors"):
                                meta["authors"] = parse_authors(authors_src)
                        else:
                            blob = raw_side
                            meta = parse_metadata_from_text(blob)
                        cap_tokens |= capitalized_tokens(raw_side)
                else:
                    blob = read_pdf_text(p)
                    if not blob.strip():
                        warnings.append(f"reference_pdf_extract_failed:{p}")
                        continue
                    meta, evidence = parse_pdf_first_page_metadata(blob)
                    if "for_seeds" in label.lower() and not (meta.get("authors") or []):
                        warnings.append(f"seed_authors_unparsed_pdf:{p.name}")
                    cap_tokens |= capitalized_tokens(blob)
            else:
                continue

            title = str(meta.get("title", "")).strip() or p.stem
            authors = meta.get("authors") if isinstance(meta.get("authors"), list) else []
            out.append(
                RefCandidate(
                    source_path=str(p),
                    title=title,
                    authors=authors if authors else [],
                    year=str(meta.get("year", "") or ""),
                    arxiv_id=str(meta.get("arxiv_id", "") or ""),
                    doi=str(meta.get("doi", "") or ""),
                    abstract=str(meta.get("abstract", "") or ""),
                    link=str(meta.get("link", "") or ""),
                    text=normalize_text(blob),
                    capitalized_tokens=sorted(cap_tokens),
                    extraction_evidence=evidence if isinstance(evidence, dict) else {},
                )
            )
        except Exception as e:
            warnings.append(f"reference_parse_failed:{p}:{e}")

    return out


def tfidf_terms(docs_tokens: List[List[str]]) -> Tuple[List[Tuple[str, float]], Dict[str, float]]:
    n_docs = max(1, len(docs_tokens))
    tf = Counter()
    df = Counter()
    for toks in docs_tokens:
        tf.update(toks)
        df.update(set(toks))

    scores: List[Tuple[str, float]] = []
    for term, term_tf in tf.items():
        term_df = df.get(term, 0)
        if term_df < DF_MIN:
            continue
        if (term_df / n_docs) > DF_RATIO_MAX:
            continue
        idf = math.log((n_docs + 1) / (term_df + 1)) + 1.0
        scores.append((term, term_tf * idf))

    scores.sort(key=lambda x: (-x[1], x[0]))
    return scores, {k: v for k, v in scores}


def filter_tokens(
    tokens: List[str],
    source_type: str,
    author_name_tokens: Set[str],
    ref_cap_tokens: Set[str],
    dropped_by_reason: Dict[str, Counter],
) -> List[str]:
    out: List[str] = []
    hard_sw = STOPWORDS | TEX_CONTROL_WORDS
    for t in tokens:
        reason = ""
        if t in hard_sw:
            reason = "hard_stopword"
        elif t in author_name_tokens:
            reason = "author_name"
        elif source_type == "references" and t in ref_cap_tokens:
            reason = "capitalized_ref_token"

        if reason:
            dropped_by_reason.setdefault(reason, Counter())[t] += 1
            continue
        out.append(t)
    return out


def ngrams_from_blocks(block_tokens: List[List[str]], n: int, top_k: int) -> List[str]:
    tf = Counter()
    df = Counter()
    n_docs = max(1, len(block_tokens))
    for toks in block_tokens:
        grams = [" ".join(toks[i:i + n]) for i in range(0, max(0, len(toks) - n + 1))]
        tf.update(grams)
        df.update(set(grams))
    ranked: List[Tuple[str, float]] = []
    for g, c in tf.items():
        gdf = df.get(g, 0)
        if gdf < DF_MIN:
            continue
        if (gdf / n_docs) > DF_RATIO_MAX:
            continue
        idf = math.log((n_docs + 1) / (gdf + 1)) + 1.0
        ranked.append((g, c * idf))
    ranked.sort(key=lambda x: (-x[1], x[0]))
    return [g for g, _ in ranked[:top_k]]


def dedup_keep_order(items: List[str]) -> List[str]:
    out: List[str] = []
    seen: Set[str] = set()
    for x in items:
        x = x.strip()
        if x and x not in seen:
            seen.add(x)
            out.append(x)
    return out


def first_sentence(text: str) -> str:
    s = re.split(r"(?<=[.!?])\s+", text.strip())
    return s[0].strip() if s and s[0].strip() else ""


def validate_output_payload(payload: Dict[str, object]) -> None:
    required_top = {"version", "task_id", "generated_at_utc", "source_files", "profile"}
    if not required_top.issubset(payload.keys()):
        raise RuntimeError(f"SCHEMA_VALIDATION_ERROR missing_top_keys={sorted(list(required_top - set(payload.keys())))}")
    profile = payload.get("profile", {})
    if not isinstance(profile, dict):
        raise RuntimeError("SCHEMA_VALIDATION_ERROR profile_not_object")
    seed_summary = profile.get("seed_summary", {})
    if not isinstance(seed_summary, dict):
        raise RuntimeError("SCHEMA_VALIDATION_ERROR seed_summary_not_object")
    status = str(seed_summary.get("status", ""))
    if status not in {"ok", "warn"}:
        raise RuntimeError(f"SCHEMA_VALIDATION_ERROR invalid_status={status}")
    seeds = profile.get("seed_papers", [])
    if not isinstance(seeds, list):
        raise RuntimeError("SCHEMA_VALIDATION_ERROR seed_papers_not_array")
    if len(seeds) > SEED_TOP_K:
        raise RuntimeError(f"SCHEMA_VALIDATION_ERROR seed_papers_exceeds_cap={len(seeds)}>{SEED_TOP_K}")


def infer_field(keyword_tokens: List[str], corpus_tokens: Set[str]) -> Tuple[str, float, List[str]]:
    candidates = {
        "neutrino phenomenology": {"neutrino", "oscillation", "flavor", "baseline", "mixing"},
        "ultralight dark matter": {"dark", "matter", "uldm", "ultralight", "scalar", "axion"},
        "hep-ph": {"bsm", "collider", "qcd", "effective", "lagrangian"},
        "astro-ph": {"cosmology", "galaxy", "cmb", "supernova", "astrophysical"},
        "physics": {"experiment", "theory", "simulation", "analysis"},
    }
    token_set = set(keyword_tokens) | corpus_tokens
    scores: Dict[str, int] = {}
    evidence: Dict[str, List[str]] = {}
    for field, terms in candidates.items():
        hit = sorted([t for t in terms if t in token_set])
        scores[field] = len(hit)
        evidence[field] = hit
    field = max(scores, key=lambda k: (scores[k], k))
    total = sum(scores.values())
    conf = 0.0 if total == 0 else round(scores[field] / total, 3)
    if scores[field] == 0:
        return "physics", 0.2, []
    return field, conf, evidence[field]


def evaluate_requirements(
    keywords: List[str],
    bigrams: List[str],
    trigrams: List[str],
    field: str,
    field_confidence: float,
    complete_seed_count: int,
    min_complete_seeds: int,
) -> Tuple[bool, List[str], Dict[str, object]]:
    kw_unique = []
    seen = set()
    for k in keywords:
        kl = str(k).strip().lower()
        if not kl or kl in seen:
            continue
        seen.add(kl)
        kw_unique.append(kl)

    banned_found = sorted([k for k in kw_unique if k in TEX_CONTROL_WORDS])
    phrase_count = len([x for x in dedup_keep_order(trigrams + bigrams) if " " in x.strip()])
    domain_tokens = [
        k for k in kw_unique
        if k not in STOPWORDS and k not in LATEX_STOPWORDS and len(k) >= 5 and " " not in k
    ]
    fieldname_hits = [k for k in kw_unique if k in REF_FIELDNAME_TOKENS]
    fieldname_ratio = (len(fieldname_hits) / max(1, len(kw_unique)))

    has_keywords_count = len(kw_unique) >= MIN_KEYWORDS
    has_keywords_banned = len(banned_found) == 0
    has_keywords_shape = (phrase_count >= MIN_KEYWORD_PHRASES) or (len(domain_tokens) >= MIN_DOMAIN_TOKENS)
    has_keywords_fieldname = fieldname_ratio <= MAX_FIELDNAME_KEYWORD_RATIO
    has_keywords_good = has_keywords_count and has_keywords_banned and has_keywords_shape and has_keywords_fieldname
    has_field = bool(str(field).strip()) and (field_confidence >= 0.2)
    missing: List[str] = []
    if not has_field:
        missing.append("field")
    if not has_keywords_good:
        missing.append("keywords(quality_gate)")

    diagnostics = {
        "has_field": has_field,
        "has_keywords_good": has_keywords_good,
        "complete_seed_count": complete_seed_count,
        "min_complete_seeds": min_complete_seeds,
        "keyword_quality": {
            "unique_count": len(kw_unique),
            "min_unique_required": MIN_KEYWORDS,
            "banned_found": banned_found,
            "phrase_count": phrase_count,
            "min_phrase_required": MIN_KEYWORD_PHRASES,
            "domain_token_count": len(domain_tokens),
            "min_domain_tokens_required": MIN_DOMAIN_TOKENS,
            "references_fieldname_ratio": round(fieldname_ratio, 4),
            "references_fieldname_max_ratio": MAX_FIELDNAME_KEYWORD_RATIO,
            "references_fieldname_hits": fieldname_hits,
        },
    }
    return len(missing) == 0, missing, diagnostics


def to_rel(root: Path, p: Path) -> str:
    try:
        return str(p.resolve().relative_to(root.resolve()))
    except Exception:
        return str(p)


def canonical_seed_key(seed: Dict[str, object]) -> str:
    doi = str(seed.get("doi", "") or "").strip().lower()
    if doi:
        return f"doi:{doi}"
    arx = str(seed.get("arxiv_id", "") or "").strip().lower()
    if arx:
        return f"arxiv:{arx}"
    title = str(seed.get("title", "") or "").strip().lower()
    if title:
        return f"title:{hash(title)}"
    return f"path:{seed.get('source_path', '')}"


def normalize_arxiv_id(raw: str) -> str:
    s = str(raw or "").strip()
    if not s:
        return ""
    m = ARXIV_ID_RE.search(s)
    if m:
        return m.group(1)
    spaced = re.search(r"\b(\d{4})\s+(\d{4,5}(?:v\d+)?)\b", s)
    if spaced:
        return f"{spaced.group(1)}.{spaced.group(2)}"
    dotted = re.search(r"\b(\d{4})[._-](\d{4,5}(?:v\d+)?)\b", s)
    if dotted:
        return f"{dotted.group(1)}.{dotted.group(2)}"
    return s


def validate_seed(seed: Dict[str, object], warnings: List[str], emit_warnings: bool = True) -> Tuple[bool, List[str]]:
    missing: List[str] = []
    title = str(seed.get("title", "") or "").strip()
    if not title:
        missing.append("title")
    authors = seed.get("authors")
    has_authors = isinstance(authors, list) and len([a for a in authors if str(a).strip()]) >= 1
    has_linkable_id = bool(
        str(seed.get("link", "") or "").strip()
        or str(seed.get("arxiv_id", "") or "").strip()
        or str(seed.get("doi", "") or "").strip()
    )
    # COMPLETE: title + (authors or link/arxiv/doi). Abstract is optional.
    if title and not (has_authors or has_linkable_id):
        missing.append("authors_or_linkable_id")
    arxiv_id = seed.get("arxiv_id")
    if arxiv_id is not None and str(arxiv_id).strip() == "":
        seed["arxiv_id"] = None

    # Keep author list stable for downstream consumers.
    if emit_warnings and (not has_authors) and title:
        seed["authors"] = ["UNKNOWN"]
        warnings.append(f"seed_authors_unknown:{title or seed.get('source_path','unknown')}")

    return len(missing) == 0, missing


def finalize_seed_row(seed: Dict[str, object], warnings: List[str]) -> Dict[str, object]:
    row = dict(seed)
    title = str(row.get("title", "") or "").strip()
    ok, missing = validate_seed(row, warnings, emit_warnings=True)
    if not title:
        row["completeness"] = "INVALID"
    elif ok:
        row["completeness"] = "COMPLETE"
    else:
        row["completeness"] = "PARTIAL"
    row["missing_fields"] = missing
    row.pop("_score", None)
    row.pop("_priority", None)
    return row


def seed_completeness_rank(seed: Dict[str, object]) -> int:
    title = str(seed.get("title", "") or "").strip()
    ok, _ = validate_seed(dict(seed), [], emit_warnings=False)
    if not title:
        return 2  # INVALID
    if ok:
        return 0  # COMPLETE
    return 1  # PARTIAL


def seed_source_rank(seed: Dict[str, object]) -> int:
    src = seed.get("source", {})
    kind = ""
    if isinstance(src, dict):
        kind = str(src.get("kind", "")).strip().lower()
    mapping = {
        "references_for_seeds": 0,
        "bib": 1,
        "tex_cite_bib": 2,
        "tex_cite_key": 2,
        "references_general": 3,
        "notes_reference": 4,
    }
    return mapping.get(kind, 9)


def summarize_stage(name: str, attempted: bool, added: int, seeds: List[Dict[str, object]]) -> Dict[str, object]:
    complete_count = 0
    partial_count = 0
    missing_counter: Counter = Counter()
    for s in seeds:
        missing = s.get("missing_fields", [])
        if s.get("completeness") == "COMPLETE":
            complete_count += 1
        else:
            partial_count += 1
            if isinstance(missing, list):
                for x in missing:
                    missing_counter[str(x)] += 1
    top_missing = [f"{k}:{v}" for k, v in missing_counter.most_common(5)]
    return {
        "stage": name,
        "attempted": attempted,
        "added": added,
        "total_candidates": len(seeds),
        "complete_count": complete_count,
        "partial_count": partial_count,
        "top_missing_fields": top_missing,
    }


def arxiv_lookup(arxiv_id: str, timeout_sec: float = 15.0) -> Dict[str, object]:
    base = os.environ.get("PAPER_PROFILE_ARXIV_API_BASE", "http://export.arxiv.org/api/query")
    q = urllib.parse.urlencode({"id_list": arxiv_id})
    url = f"{base}?{q}"
    req = urllib.request.Request(url, headers={"User-Agent": "paper-profile/1.0"})
    with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
        xml_text = resp.read().decode("utf-8", errors="ignore")
    root = ET.fromstring(xml_text)
    ns = {"a": "http://www.w3.org/2005/Atom"}
    entry = root.find("a:entry", ns)
    if entry is None:
        return {}
    title = (entry.findtext("a:title", default="", namespaces=ns) or "").strip()
    summary = (entry.findtext("a:summary", default="", namespaces=ns) or "").strip()
    authors = [x.text.strip() for x in entry.findall("a:author/a:name", ns) if x.text and x.text.strip()]
    year = None
    published = (entry.findtext("a:published", default="", namespaces=ns) or "").strip()
    if published[:4].isdigit():
        year = int(published[:4])
    return {
        "title": title,
        "abstract": summary,
        "authors": authors,
        "year": year,
        "link": f"https://arxiv.org/abs/{arxiv_id}",
    }


def crossref_lookup(doi: str, timeout_sec: float = 15.0) -> Dict[str, object]:
    url = f"https://api.crossref.org/works/{urllib.parse.quote(doi)}"
    req = urllib.request.Request(url, headers={"User-Agent": "paper-profile/1.0"})
    with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
        obj = json.loads(resp.read().decode("utf-8", errors="ignore"))
    msg = obj.get("message", {}) if isinstance(obj, dict) else {}
    title = ""
    if isinstance(msg.get("title"), list) and msg["title"]:
        title = str(msg["title"][0]).strip()
    authors: List[str] = []
    for a in msg.get("author", []) if isinstance(msg.get("author"), list) else []:
        g = str(a.get("given", "")).strip()
        f = str(a.get("family", "")).strip()
        name = " ".join([x for x in [g, f] if x]).strip()
        if name:
            authors.append(name)
    year = None
    parts = (((msg.get("issued") or {}).get("date-parts") or [[None]])[0] if isinstance(msg.get("issued"), dict) else [None])
    if parts and str(parts[0]).isdigit():
        year = int(parts[0])
    abstract = str(msg.get("abstract", "") or "").strip()
    if abstract:
        abstract = re.sub(r"<[^>]+>", " ", abstract)
        abstract = re.sub(r"\s+", " ", abstract).strip()
    return {
        "title": title,
        "authors": authors,
        "year": year,
        "abstract": abstract,
        "doi": doi,
        "link": f"https://doi.org/{doi}",
    }


def inspire_lookup(title: str, authors: List[str], timeout_sec: float = 15.0) -> Dict[str, object]:
    q = title.strip()
    if not q:
        return {}
    url = "https://inspirehep.net/api/literature?" + urllib.parse.urlencode({"q": q, "size": 1})
    req = urllib.request.Request(url, headers={"User-Agent": "paper-profile/1.0"})
    with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
        obj = json.loads(resp.read().decode("utf-8", errors="ignore"))
    hits = obj.get("hits", {}).get("hits", []) if isinstance(obj, dict) else []
    if not hits:
        return {}
    meta = hits[0].get("metadata", {}) if isinstance(hits[0], dict) else {}
    title_v = ""
    if isinstance(meta.get("titles"), list) and meta["titles"]:
        title_v = str(meta["titles"][0].get("title", "")).strip()
    abs_v = ""
    if isinstance(meta.get("abstracts"), list) and meta["abstracts"]:
        abs_v = str(meta["abstracts"][0].get("value", "")).strip()
    out_authors: List[str] = []
    for a in meta.get("authors", []) if isinstance(meta.get("authors"), list) else []:
        n = str(a.get("full_name", "")).strip()
        if n:
            out_authors.append(n)
    year_v = meta.get("preprint_date", "") or meta.get("earliest_date", "")
    year = int(year_v[:4]) if isinstance(year_v, str) and len(year_v) >= 4 and year_v[:4].isdigit() else None
    return {
        "title": title_v,
        "authors": out_authors,
        "year": year,
        "abstract": abs_v,
    }


def try_complete_online(
    seeds: List[Dict[str, object]],
    cache_dir: Path,
    failfast: bool,
) -> Tuple[List[Dict[str, object]], Dict[str, object], List[str]]:
    cache_dir.mkdir(parents=True, exist_ok=True)
    out: List[Dict[str, object]] = []
    warn: List[str] = []
    online_meta: Dict[str, object] = {
        "attempted": False,
        "backend": "none",
        "fail_reason": None,
        "queries": [],
    }
    network_unavailable = False
    for s in seeds:
        row = dict(s)
        # Enrichment only fills missing fields; it never blocks success.
        needs_fill = (
            not str(row.get("title", "") or "").strip()
            or not (isinstance(row.get("authors"), list) and len([a for a in row.get("authors", []) if str(a).strip()]) > 0)
            or not str(row.get("abstract", "") or "").strip()
            or not str(row.get("link", "") or "").strip()
        )
        if not needs_fill:
            out.append(row)
            continue

        backend = "none"
        query = ""
        lookup_meta: Dict[str, object] = {}
        arxiv_id = normalize_arxiv_id(str(row.get("arxiv_id", "") or ""))
        doi = str(row.get("doi", "") or "").strip()
        title = str(row.get("title", "") or "").strip()

        if arxiv_id:
            backend = "arxiv"
            query = arxiv_id
        elif doi:
            backend = "crossref"
            query = doi
        elif title:
            backend = "inspire"
            query = title[:120]
        else:
            out.append(row)
            continue

        online_meta["attempted"] = True
        online_meta["backend"] = backend
        cast_queries = online_meta.get("queries")
        if isinstance(cast_queries, list):
            cast_queries.append(f"{backend}:{query}")

        cache_key = re.sub(r"[^a-zA-Z0-9_.-]", "_", f"{backend}_{query}")[:180]
        cache_path = cache_dir / f"{cache_key}.json"
        legacy_cache = None
        if backend == "arxiv" and arxiv_id:
            legacy_cache = cache_dir / f"{arxiv_id}.json"
        elif backend == "crossref" and doi:
            legacy_cache = cache_dir / f"{doi}.json"
        try:
            if cache_path.exists():
                lookup_meta = json.loads(cache_path.read_text(encoding="utf-8"))
            elif legacy_cache is not None and legacy_cache.exists():
                lookup_meta = json.loads(legacy_cache.read_text(encoding="utf-8"))
            else:
                if backend == "arxiv":
                    lookup_meta = arxiv_lookup(arxiv_id)
                elif backend == "crossref":
                    lookup_meta = crossref_lookup(doi)
                else:
                    lookup_meta = inspire_lookup(title, row.get("authors", []) if isinstance(row.get("authors"), list) else [])
                cache_path.write_text(json.dumps(lookup_meta, indent=2), encoding="utf-8")
        except Exception as e:
            msg = str(e)
            if failfast:
                raise RuntimeError(f"NETWORK_LOOKUP_FAILED backend={backend} query={query} cause={e}")
            if ("Operation not permitted" in msg or "Name or service not known" in msg or "nodename nor servname" in msg):
                if not network_unavailable:
                    warn.append("WARNING NETWORK_UNAVAILABLE")
                    network_unavailable = True
                online_meta["fail_reason"] = f"backend={backend} query={query} cause={e}"
            else:
                warn.append(f"WARNING ONLINE_LOOKUP_FAILED backend={backend} query={query} cause={e}")
                online_meta["fail_reason"] = f"backend={backend} query={query} cause={e}"
            out.append(row)
            continue

        if lookup_meta.get("title") and not row.get("title"):
            row["title"] = lookup_meta["title"]
        if lookup_meta.get("abstract") and not row.get("abstract"):
            row["abstract"] = lookup_meta["abstract"]
        if lookup_meta.get("authors") and (not isinstance(row.get("authors"), list) or not row.get("authors")):
            row["authors"] = lookup_meta["authors"]
        if lookup_meta.get("year") and not row.get("year"):
            row["year"] = lookup_meta["year"]
        if lookup_meta.get("link") and not row.get("link"):
            row["link"] = lookup_meta["link"]
        if lookup_meta.get("doi") and not row.get("doi"):
            row["doi"] = lookup_meta["doi"]
        if lookup_meta.get("arxiv_id") and not row.get("arxiv_id"):
            row["arxiv_id"] = lookup_meta["arxiv_id"]
        out.append(row)
    return out, online_meta, warn


def parse_request_bool(request_text: str, keys: List[str], default: bool) -> bool:
    for key in keys:
        m = re.search(rf"(?mi)^\s*{re.escape(key)}\s*:\s*(true|false|yes|no|1|0)\s*$", request_text)
        if m:
            return m.group(1).lower() in {"true", "yes", "1"}
    return default


def parse_request_int(request_text: str, keys: List[str], default: int) -> int:
    for key in keys:
        m = re.search(rf"(?mi)^\s*{re.escape(key)}\s*:\s*(\d+)\s*$", request_text)
        if m:
            try:
                return int(m.group(1))
            except Exception:
                return default
    return default


def parse_request_config(request_text: str, cli_online: bool) -> Dict[str, object]:
    env_online = str(os.environ.get("ONLINE_LOOKUP", "0")).lower() in {"1", "true", "yes"}
    env_net_allowed = str(os.environ.get("NET_ALLOWED", "0")).lower() in {"1", "true", "yes"}
    env_online_failfast = str(os.environ.get("ONLINE_FAILFAST", "1")).lower() in {"1", "true", "yes"}
    env_min_complete = os.environ.get("PAPER_PROFILE_MIN_COMPLETE_SEEDS", "").strip()
    min_complete = MIN_COMPLETE_SEEDS
    if env_min_complete.isdigit():
        min_complete = max(1, int(env_min_complete))

    request_online_lookup = parse_request_bool(
        request_text,
        keys=["online_lookup", "request.flags.online_lookup"],
        default=env_online,
    )
    cli_online_requested = cli_online or env_online

    online_failfast = parse_request_bool(
        request_text,
        keys=["online_failfast", "request.flags.online_failfast"],
        default=env_online_failfast,
    )
    min_complete = parse_request_int(
        request_text,
        keys=["min_complete_seeds", "request.flags.min_complete_seeds"],
        default=min_complete,
    )
    min_complete = max(1, min_complete)
    return {
        "request_online_lookup": request_online_lookup,
        "cli_online_requested": cli_online_requested,
        "net_allowed": env_net_allowed,
        "online_failfast": online_failfast,
        "min_complete_seeds": min_complete,
    }


def build_profile(
    root: Path,
    task_id: str,
    request_path: Path,
    user_paper: Path,
    user_notes: Path,
    user_refs_for_seeds: Path,
    out_json: Path,
    out_report: Path,
    resolved_json: Path,
    online_lookup_cli: bool,
) -> int:
    warnings: List[str] = []
    attempts: List[str] = []
    stage_breakdown: List[Dict[str, object]] = []

    request_text = slurp(request_path)
    cfg = parse_request_config(request_text=request_text, cli_online=online_lookup_cli)
    request_online_lookup = bool(cfg["request_online_lookup"])
    cli_online_requested = bool(cfg["cli_online_requested"])
    net_allowed = bool(cfg["net_allowed"])
    online_failfast = bool(cfg["online_failfast"])
    min_complete_seeds = int(cfg["min_complete_seeds"])
    online_requested = request_online_lookup or cli_online_requested
    online_attempted = False
    online_backend_used = "none"
    online_fail_reason: Optional[str] = None
    validation_phase = "pre_online"
    if online_requested and not net_allowed and online_failfast:
        raise RuntimeError(
            "Need online metadata completion (abstract/title/authors). Re-run: "
            f"./bin/agenthub run --task {task_id} --online --net --yes|--no"
        )
    if online_requested and not net_allowed:
        warnings.append("WARNING NETWORK_UNAVAILABLE")

    # Discovery order:
    # 1) USER/references/for_seeds (primary and only reference seed pool)
    # 2) USER/paper sources (.tex/.bib/.pdf/.md/.txt) for keywords + bib fallback seeds.
    ref_candidates_primary = discover_reference_candidates(
        user_refs_for_seeds, warnings, label="USER/references/for_seeds"
    )
    refs_root = user_refs_for_seeds.parent if user_refs_for_seeds.name == "for_seeds" else user_refs_for_seeds
    ref_candidates_secondary: List[RefCandidate] = []
    if refs_root != user_refs_for_seeds:
        # Reporting/diagnostics only; these are not eligible as seed candidates.
        ref_candidates_secondary_all = discover_reference_candidates(
            refs_root, warnings, label="USER/references"
        )
        for rc in ref_candidates_secondary_all:
            try:
                rp = Path(rc.source_path).resolve()
                if rp.is_relative_to(user_refs_for_seeds.resolve()):
                    continue
            except Exception:
                pass
            ref_candidates_secondary.append(rc)

    tex_candidates = sorted([p for p in user_paper.rglob("*.tex") if p.is_file()]) if user_paper.exists() else []
    tex_files: List[Path] = []
    main_tex: Optional[Path] = None
    if tex_candidates:
        main_tex = choose_main_tex(tex_candidates)
        tex_files = expand_tex_graph(main_tex)

    bib_files = discover_bib_files(tex_files, user_paper) if tex_files else sorted(
        [p.resolve() for p in user_paper.rglob("*.bib") if p.is_file()]
    )
    # Paper-local auxiliary docs are used for keyword/field extraction only.
    paper_ref_candidates = discover_reference_candidates(
        user_paper, warnings, label="USER/paper"
    )

    note_files = discover_notes(user_notes)
    note_ref_candidates = discover_note_reference_candidates(note_files)
    cite_keys = collect_cite_keys(tex_files)
    cite_set = set(cite_keys)
    structured_phrases = extract_structured_phrases(tex_files)

    all_tex_text = "\n".join(slurp(p) for p in tex_files)
    blocks = extract_blocks(slurp(main_tex)) if main_tex is not None else {"title": "", "abstract": "", "introduction": ""}
    title = blocks.get("title", "")
    abstract = blocks.get("abstract", "")
    intro = blocks.get("introduction", "")
    paper_ref_text = " ".join([r.title + " " + r.abstract + " " + r.text for r in paper_ref_candidates])
    blocks_for_ngrams = [x for x in [title, abstract, intro] if x.strip()]
    if not blocks_for_ngrams:
        fallback_block = clean_latex_text(all_tex_text + " " + paper_ref_text)
        if fallback_block.strip():
            blocks_for_ngrams = [fallback_block]

    bib_entries: List[BibEntry] = []
    for b in bib_files:
        try:
            bib_entries.extend(parse_bib_entries(slurp(b), source_path=to_rel(root, b)))
        except Exception as e:
            warnings.append(f"bib_parse_failed:{to_rel(root,b)}:{e}")

    has_any_sources = bool(tex_files or note_files or bib_files or ref_candidates_primary or ref_candidates_secondary or paper_ref_candidates)
    if not has_any_sources:
        raise RuntimeError("MISSING_MANUSCRIPT_SOURCES: no tex/notes/references/bib discovered")

    unresolved_cites = [k for k in cite_keys if k not in {e.bibkey for e in bib_entries}]

    author_name_set: Set[str] = set()
    for e in bib_entries:
        author_name_set |= author_name_tokens_from_authors(parse_authors(e.fields.get("author", "")))
    for r in ref_candidates_primary + paper_ref_candidates:
        author_name_set |= author_name_tokens_from_authors(r.authors)
    ref_cap_tokens: Set[str] = set()
    for r in ref_candidates_primary + paper_ref_candidates:
        ref_cap_tokens |= set(r.capitalized_tokens)

    # Keyword extraction corpus with source-aware filtering and hard filters.
    docs_tokens: List[List[str]] = []
    filtered_token_counts = {
        "tex": {"before": 0, "after": 0},
        "notes": {"before": 0, "after": 0},
        "bib": {"before": 0, "after": 0},
        "references": {"before": 0, "after": 0},
    }
    dropped_by_reason: Dict[str, Counter] = {}

    for b in blocks_for_ngrams:
        raw = tokenize(clean_latex_text(b))
        filtered = filter_tokens(raw, "tex", author_name_set, ref_cap_tokens, dropped_by_reason)
        filtered_token_counts["tex"]["before"] += len(raw)
        filtered_token_counts["tex"]["after"] += len(filtered)
        docs_tokens.append(filtered)
    for nf in note_files:
        raw = tokenize(clean_latex_text(slurp(nf)))
        filtered = filter_tokens(raw, "notes", author_name_set, ref_cap_tokens, dropped_by_reason)
        filtered_token_counts["notes"]["before"] += len(raw)
        filtered_token_counts["notes"]["after"] += len(filtered)
        docs_tokens.append(filtered)
    for e in bib_entries:
        # Source-aware bib parsing: only semantic value fields.
        bib_semantic = " ".join([e.fields.get("title", ""), e.fields.get("keywords", ""), e.fields.get("abstract", "")])
        raw = tokenize(bib_semantic)
        filtered = filter_tokens(raw, "bib", author_name_set, ref_cap_tokens, dropped_by_reason)
        filtered_token_counts["bib"]["before"] += len(raw)
        filtered_token_counts["bib"]["after"] += len(filtered)
        docs_tokens.append(filtered)
    for r in ref_candidates_primary + paper_ref_candidates:
        raw = tokenize(r.title + " " + r.abstract + " " + r.text)
        filtered = filter_tokens(raw, "references", author_name_set, ref_cap_tokens, dropped_by_reason)
        filtered_token_counts["references"]["before"] += len(raw)
        filtered_token_counts["references"]["after"] += len(filtered)
        docs_tokens.append(filtered)

    attempts.append("tfidf:paper+notes+references+bib")
    unigram_scores, unigram_map = tfidf_terms(docs_tokens)
    unigrams = [u for u, _ in unigram_scores[:TOP_K_KEYWORDS]]
    ngram_block_tokens = [tokenize(clean_latex_text(x)) for x in blocks_for_ngrams]
    bigrams = ngrams_from_blocks(ngram_block_tokens, 2, TOP_K_BIGRAMS)
    trigrams = ngrams_from_blocks(ngram_block_tokens, 3, TOP_K_TRIGRAMS)
    keywords = dedup_keep_order(structured_phrases + trigrams + bigrams + unigrams)
    keywords = [
        k for k in keywords
        if k.lower() not in STOPWORDS
        and k.lower() not in author_name_set
        and k.lower() not in ref_cap_tokens
    ]

    if len(keywords) < MIN_KEYWORDS:
        attempts.append("fallback:freq_from_full_tex_notes_refs")
        fallback_tokens = tokenize(clean_latex_text(all_tex_text))
        for nf in note_files:
            fallback_tokens += tokenize(clean_latex_text(slurp(nf)))
        for r in ref_candidates_primary + paper_ref_candidates:
            fallback_tokens += tokenize(r.title + " " + r.abstract + " " + r.text)
        fallback_tokens = filter_tokens(
            fallback_tokens, "references", author_name_set, ref_cap_tokens, dropped_by_reason
        )
        for tok, _ in Counter(fallback_tokens).most_common(200):
            if tok not in keywords and tok not in STOPWORDS:
                keywords.append(tok)
            if len(keywords) >= MIN_KEYWORDS:
                break

    if len(keywords) < MIN_KEYWORDS:
        warnings.append(f"keywords_nontrivial_failed:found={len(keywords)}<required={MIN_KEYWORDS};attempts={';'.join(attempts)}")

    if not any(" " in k for k in keywords[:10]):
        warnings.append("keyword_quality_low:mostly_single_tokens_no_strong_phrases")

    corpus_tokens = set(tokenize(clean_latex_text(all_tex_text)))
    field, field_confidence, field_evidence_terms = infer_field(tokenize(" ".join(keywords[:30])), corpus_tokens)
    if not field.strip():
        warnings.append("field_detected_failed:no_field_signal")
    elif field == "physics" and field_confidence < 0.35:
        warnings.append("field_quality_low:generic_field_with_low_confidence")

    # Build seed candidates with progressive fallback:
    # S0 for_seeds -> S1 bib -> S2 tex cites -> S3 references (general) -> S4 online
    kw_weights = dict(unigram_map)
    for p in bigrams[:TOP_K_BIGRAMS]:
        for t in p.split():
            kw_weights[t] = kw_weights.get(t, 0.0) + 0.4
    for p in trigrams[:TOP_K_TRIGRAMS]:
        for t in p.split():
            kw_weights[t] = kw_weights.get(t, 0.0) + 0.5

    seed_candidates: List[Dict[str, object]] = []
    seen_seed_keys: Set[str] = set()

    def merge_stage_candidates(rows: List[Dict[str, object]], priority: int) -> int:
        added = 0
        for row in rows:
            x = dict(row)
            x["_priority"] = priority
            key = canonical_seed_key(x)
            if key in seen_seed_keys:
                continue
            seen_seed_keys.add(key)
            seed_candidates.append(x)
            added += 1
        seed_candidates.sort(key=lambda x: (int(x.get("_priority", 9)), -float(x.get("_score", 0.0)), str(x.get("title", ""))))
        return added

    def finalize_candidates(rows: List[Dict[str, object]]) -> List[Dict[str, object]]:
        out_rows: List[Dict[str, object]] = []
        for row in rows:
            z = finalize_seed_row(row, warnings)
            if isinstance(z.get("source"), dict):
                z["source_path"] = z["source"].get("path", z.get("source_path", ""))
            out_rows.append(z)
        return out_rows

    def count_complete(rows: List[Dict[str, object]]) -> int:
        return len([r for r in rows if r.get("completeness") == "COMPLETE"])

    # S0: USER/references/for_seeds/*
    attempts.append("S0:references_for_seeds")
    s0_rows: List[Dict[str, object]] = []
    for rc in ref_candidates_primary:
        rtoks = set(tokenize(rc.title + " " + rc.abstract + " " + rc.text))
        matched = [t for t in sorted(rtoks) if t in kw_weights]
        s0_rows.append({
            "title": rc.title,
            "authors": rc.authors,
            "arxiv_id": rc.arxiv_id or None,
            "abstract": rc.abstract,
            "link": rc.link or (f"https://arxiv.org/abs/{rc.arxiv_id}" if rc.arxiv_id else ""),
            "year": int(rc.year) if rc.year.isdigit() else None,
            "doi": rc.doi or None,
            "source": {"kind": "references_for_seeds", "path": rc.source_path},
            "source_path": rc.source_path,
            "seed_extraction_evidence": rc.extraction_evidence if isinstance(rc.extraction_evidence, dict) else {},
            "why": matched[:8],
            "cited": False,
            "_score": sum(kw_weights.get(t, 0.0) for t in matched) + 5.0,
        })
    s0_added = merge_stage_candidates(s0_rows, priority=0)
    finalized = finalize_candidates(seed_candidates)
    stage_breakdown.append(summarize_stage("S0:references_for_seeds", True, s0_added, finalized))

    # S1: USER/paper/**/*.bib
    attempts.append("S1:paper_bib")
    s1_rows: List[Dict[str, object]] = []
    for e in bib_entries:
        title_b = e.fields.get("title", "")
        authors = parse_authors(e.fields.get("author", ""))
        arxiv_id = normalize_arxiv_id(e.fields.get("eprint", ""))
        doi = e.fields.get("doi", "")
        link = ""
        if arxiv_id:
            link = f"https://arxiv.org/abs/{arxiv_id}"
        elif doi:
            link = f"https://doi.org/{doi}"
        elif e.fields.get("url"):
            link = e.fields.get("url", "")
        abstract_b = e.fields.get("abstract", "")
        etoks = set(tokenize(" ".join([title_b, e.fields.get("keywords", ""), e.fields.get("author", ""), abstract_b])))
        matched = [t for t in sorted(etoks) if t in kw_weights]
        year_val = int(e.fields.get("year")) if str(e.fields.get("year", "")).isdigit() else None
        rank_score = sum(kw_weights.get(t, 0.0) for t in matched)
        if year_val is not None:
            rank_score += float(year_val) / 10000.0
        if e.bibkey in cite_set:
            rank_score += 2.0
        s1_rows.append({
            "title": title_b,
            "authors": authors,
            "arxiv_id": arxiv_id or None,
            "abstract": abstract_b,
            "link": link,
            "year": year_val,
            "doi": doi or None,
            "source": {"kind": "bib", "path": e.source_path},
            "source_path": e.source_path,
            "why": matched[:8],
            "cited": e.bibkey in cite_set,
            "bibkey": e.bibkey,
            "_score": rank_score,
        })
    s1_added = merge_stage_candidates(s1_rows, priority=1)
    finalized = finalize_candidates(seed_candidates)
    stage_breakdown.append(summarize_stage("S1:paper_bib", True, s1_added, finalized))

    # S2: USER/paper/**/*.tex citations
    attempts.append("S2:paper_tex_citations")
    bib_map = {e.bibkey: e for e in bib_entries}
    s2_rows: List[Dict[str, object]] = []
    for key in cite_keys:
        if key in bib_map:
            e = bib_map[key]
            title_b = e.fields.get("title", "") or key
            authors = parse_authors(e.fields.get("author", ""))
            arxiv_id = normalize_arxiv_id(e.fields.get("eprint", ""))
            doi = e.fields.get("doi", "")
            link = f"https://arxiv.org/abs/{arxiv_id}" if arxiv_id else (f"https://doi.org/{doi}" if doi else e.fields.get("url", ""))
            abstract_b = e.fields.get("abstract", "")
            s2_rows.append({
                "title": title_b,
                "authors": authors,
                "arxiv_id": arxiv_id or None,
                "abstract": abstract_b,
                "link": link,
                "year": int(e.fields.get("year")) if str(e.fields.get("year", "")).isdigit() else None,
                "doi": doi or None,
                "source": {"kind": "tex_cite_bib", "path": e.source_path},
                "source_path": e.source_path,
                "why": [f"cited:{key}"],
                "cited": True,
                "bibkey": key,
                "_score": 1.5,
            })
        else:
            s2_rows.append({
                "title": key,
                "authors": [],
                "arxiv_id": None,
                "abstract": "",
                "link": "",
                "year": None,
                "doi": None,
                "source": {"kind": "tex_cite_key", "path": to_rel(root, main_tex) if main_tex else ""},
                "source_path": to_rel(root, main_tex) if main_tex else "",
                "why": [f"unresolved_cite:{key}"],
                "cited": True,
                "bibkey": key,
                "_score": 0.2,
            })
    s2_added = merge_stage_candidates(s2_rows, priority=2)
    finalized = finalize_candidates(seed_candidates)
    stage_breakdown.append(summarize_stage("S2:paper_tex_citations", True, s2_added, finalized))

    # S3: USER/references/** (excluding for_seeds)
    attempts.append("S3:references_general")
    s3_rows: List[Dict[str, object]] = []
    for rc in ref_candidates_secondary:
        rtoks = set(tokenize(rc.title + " " + rc.abstract + " " + rc.text))
        matched = [t for t in sorted(rtoks) if t in kw_weights]
        s3_rows.append({
            "title": rc.title,
            "authors": rc.authors,
            "arxiv_id": rc.arxiv_id or None,
            "abstract": rc.abstract,
            "link": rc.link or (f"https://arxiv.org/abs/{rc.arxiv_id}" if rc.arxiv_id else ""),
            "year": int(rc.year) if rc.year.isdigit() else None,
            "doi": rc.doi or None,
            "source": {"kind": "references_general", "path": rc.source_path},
            "source_path": rc.source_path,
            "why": matched[:8],
            "cited": False,
            "_score": sum(kw_weights.get(t, 0.0) for t in matched) + 0.8,
        })
    s3_added = merge_stage_candidates(s3_rows, priority=3)
    finalized = finalize_candidates(seed_candidates)
    stage_breakdown.append(summarize_stage("S3:references_general", True, s3_added, finalized))

    # S4: Explicit references discovered in notes
    attempts.append("S4:notes_references")
    s4_rows: List[Dict[str, object]] = []
    for rc in note_ref_candidates:
        s4_rows.append({
            "title": rc.title,
            "authors": rc.authors,
            "arxiv_id": rc.arxiv_id or None,
            "abstract": rc.abstract,
            "link": rc.link,
            "year": int(rc.year) if rc.year.isdigit() else None,
            "doi": rc.doi or None,
            "source": {"kind": "notes_reference", "path": rc.source_path},
            "source_path": rc.source_path,
            "why": ["notes_reference"],
            "cited": False,
            "_score": 0.5,
        })
    s4_added = merge_stage_candidates(s4_rows, priority=4)
    finalized = finalize_candidates(seed_candidates)
    stage_breakdown.append(summarize_stage("S4:notes_references", True, s4_added, finalized))

    # S5: Optional online completion for partial candidates (best-effort only).
    if online_requested and net_allowed:
        attempts.append("S5:online_lookup")
        try:
            print("Online lookup enabled: enriching seed metadata (non-blocking).")
            seed_candidates, online_meta, online_warn = try_complete_online(
                seed_candidates,
                cache_dir=root / "AGENTS" / "cache" / "online_meta",
                failfast=online_failfast,
            )
            warnings.extend(online_warn)
            online_attempted = bool(online_meta.get("attempted", False))
            online_backend_used = str(online_meta.get("backend", "none"))
            online_fail_reason = online_meta.get("fail_reason")
            # preserve ordering and dedupe after online pass
            deduped_after: List[Dict[str, object]] = []
            seen_after: Set[str] = set()
            for row in seed_candidates:
                key = canonical_seed_key(row)
                if key in seen_after:
                    continue
                seen_after.add(key)
                deduped_after.append(row)
            seed_candidates = deduped_after
            finalized = finalize_candidates(seed_candidates)
            stage_breakdown.append(summarize_stage("S5:online_lookup", True, 0, finalized))
        except Exception as e:
            if online_failfast:
                raise
            online_attempted = True
            online_backend_used = "arxiv"
            online_fail_reason = str(e)
            warnings.append(f"online_lookup_warning:{e}")
            stage_breakdown.append(summarize_stage("S5:online_lookup", True, 0, finalized))
    else:
        stage_breakdown.append(summarize_stage("S5:online_lookup", False, 0, finalized))

    # Final seed relevance scoring happens after enrichment.
    keyword_terms = dedup_keep_order(keywords[:40] + field_evidence_terms)
    keyword_set = set(tokenize(" ".join(keyword_terms)))
    for row in seed_candidates:
        seed_text = (str(row.get("title", "") or "") + " " + str(row.get("abstract", "") or "")).strip()
        toks = set(tokenize(seed_text))
        matched = [t for t in sorted(toks) if t in keyword_set]
        row["why"] = matched[:10]
        row["_score"] = float(len(matched))
        if str(row.get("cited", False)).lower() == "true" or row.get("cited") is True:
            row["_score"] += 1.0
    seed_candidates.sort(
        key=lambda x: (
            seed_completeness_rank(x),
            seed_source_rank(x),
            -float(x.get("_score", 0.0)),
            str(x.get("title", "") or "").lower(),
        )
    )
    finalized = finalize_candidates(seed_candidates)

    ranked_with_title = [r for r in finalized if str(r.get("title", "") or "").strip()]
    complete = [r for r in ranked_with_title if r.get("completeness") == "COMPLETE"]
    partial = [r for r in ranked_with_title if r.get("completeness") == "PARTIAL"]
    invalid_rows = [r for r in finalized if r.get("completeness") == "INVALID"]
    seed_found_count = len(ranked_with_title)
    if seed_found_count < min_complete_seeds:
        warnings.append(
            f"WARNING only {seed_found_count} seeds found (<{min_complete_seeds}). Proceeding with draft profile."
        )

    categories = ["hep-ph", "manuscript"] if any(t in corpus_tokens for t in {"neutrino", "dark", "matter", "uldm", "flavor"}) else ["physics", "manuscript"]
    short_blurb = first_sentence(abstract) or first_sentence(intro) or "Local manuscript profile generated from USER content."
    themes = dedup_keep_order((trigrams + bigrams)[:6]) or ["manuscript_overview", "method_summary", "related_work"]

    primary_ref_paths = [
        to_rel(root, Path(r.source_path)) if str(r.source_path).startswith(str(root)) else r.source_path
        for r in ref_candidates_primary
    ]
    secondary_ref_paths = [
        to_rel(root, Path(r.source_path)) if str(r.source_path).startswith(str(root)) else r.source_path
        for r in ref_candidates_secondary
    ]
    paper_doc_paths = [
        to_rel(root, Path(r.source_path)) if str(r.source_path).startswith(str(root)) else r.source_path
        for r in paper_ref_candidates
    ]
    merged_ref_paths = dedup_keep_order(primary_ref_paths + secondary_ref_paths)
    inputs_used = {
        "paper_tex": [to_rel(root, p) for p in tex_files],
        "paper_docs": dedup_keep_order(paper_doc_paths),
        "notes": [to_rel(root, p) for p in note_files],
        "references_for_seeds": dedup_keep_order(primary_ref_paths),
        "references_general": dedup_keep_order(secondary_ref_paths),
        "references": dedup_keep_order(merged_ref_paths),
        "bib": [to_rel(root, p) for p in bib_files],
        "keywords_source": dedup_keep_order(
            [to_rel(root, p) for p in tex_files] + [to_rel(root, p) for p in note_files]
        ),
        "references_checked": dedup_keep_order(
            primary_ref_paths + secondary_ref_paths + [to_rel(root, p) for p in bib_files]
        ),
        "seed_source_breakdown": {
            "for_seeds": len(primary_ref_paths),
            "bib": len(bib_files),
            "references_pdf_general": len([p for p in secondary_ref_paths if p.lower().endswith(".pdf")]),
            "notes_references": len(note_ref_candidates),
        },
    }

    if not inputs_used["notes"]:
        warnings.append("No USER/notes/ files found (.md/.tex/.txt)")
    if not inputs_used["keywords_source"]:
        warnings.append("No keywords_source files found (paper_tex/notes empty)")
    if not inputs_used["references_for_seeds"]:
        warnings.append("No USER/references/for_seeds/ directory or no supported files")
    if refs_root != user_refs_for_seeds and not inputs_used["references_general"]:
        warnings.append("No additional files found under USER/references outside for_seeds")
    if not inputs_used["paper_docs"]:
        warnings.append("No additional paper docs (.pdf/.md/.txt/.json) found under USER/paper")
    if not inputs_used["bib"]:
        warnings.append("No .bib files discovered from tex directives or fallback search")

    seed_rows_for_output: List[Dict[str, object]] = []
    for row in ranked_with_title[:SEED_TOP_K]:
        out_row = dict(row)
        out_row["score"] = float(row.get("_score", 0.0))
        why = row.get("why", [])
        if isinstance(why, list):
            out_row["why_terms"] = [str(x) for x in why[:8]]
        else:
            out_row["why_terms"] = []
        seed_rows_for_output.append(finalize_seed_row(out_row, warnings))

    keywords_capped = keywords[:30]
    bigrams_capped = bigrams[:20]
    trigrams_capped = trigrams[:15]
    themes_capped = themes[:8]
    field_terms_capped = field_evidence_terms[:10]

    seed_summary = {
        "found": seed_found_count,
        "ranked": len(ranked_with_title),
        "emitted": len(seed_rows_for_output),
        "min_required": min_complete_seeds,
        "status": "ok" if seed_found_count >= min_complete_seeds else "warn",
    }

    profile = {
        "field": field,
        "field_confidence": field_confidence,
        "field_evidence_terms": field_terms_capped,
        "keywords": keywords_capped,
        "bigrams": bigrams_capped,
        "trigrams": trigrams_capped,
        "structured_phrases": structured_phrases,
        "categories": categories,
        "short_blurb": short_blurb,
        "related_work_themes": themes_capped,
        "seed_summary": seed_summary,
        "seed_papers": seed_rows_for_output,
        "warnings": dedup_keep_order([str(w) for w in warnings])[:40],
    }

    dropped_flat: List[Tuple[str, str, int]] = []
    for reason, ctr in dropped_by_reason.items():
        for term, cnt in ctr.items():
            dropped_flat.append((term, reason, int(cnt)))
    dropped_flat.sort(key=lambda x: (-x[2], x[1], x[0]))
    dropped_top_terms = [
        {"term": term, "reason": reason, "count": cnt}
        for term, reason, cnt in dropped_flat[:10]
    ]

    _, missing_requirements, req_diag = evaluate_requirements(
        keywords=keywords,
        bigrams=bigrams,
        trigrams=trigrams,
        field=field,
        field_confidence=field_confidence,
        complete_seed_count=seed_found_count,
        min_complete_seeds=min_complete_seeds,
    )
    if missing_requirements:
        warnings.append("WARNING profile_quality_degraded:" + ",".join(missing_requirements))

    payload = {
        "version": "paper_profile_v6",
        "task_id": task_id,
        "generated_at_utc": now_utc(),
        "source_files": {
            "tex": inputs_used["paper_tex"],
            "bib": inputs_used["bib"],
            "references_for_seeds": inputs_used["references_for_seeds"],
            "references_general": inputs_used["references_general"],
        },
        "profile": profile,
    }

    report = [
        "# paper_profile_update Report",
        "",
        "Run completed.",
        "",
        f"- task_id: {task_id}",
        "- skill: paper_profile_update",
        f"- output_profile: {to_rel(root, out_json)}",
        f"- online_requested: {str(request_online_lookup).lower()}",
        f"- net_allowed: {str(net_allowed).lower()}",
        f"- online_attempted: {str(online_attempted).lower()}",
        f"- online_backend_used: {online_backend_used}",
        f"- online_fail_reason: {online_fail_reason if online_fail_reason else 'null'}",
        "- validation_phase: post_online",
        f"- online_failfast: {str(online_failfast).lower()}",
        f"- min_seed_count: {min_complete_seeds}",
        "",
        "## Inputs used",
        "- keywords source(s):",
        "  - paper_tex + notes + references + bib",
        "- field/domain source(s):",
        "  - paper_tex (+ notes support)",
        "- seed source(s):",
        "  - S0 USER/references/for_seeds, S1 USER/paper/**/*.bib, S2 USER/paper/**/*.tex cites, S3 USER/references/*.pdf, S4 notes refs, S5 online_lookup(optional)",
        "- paper_tex:",
    ]
    report += [f"  - {p}" for p in inputs_used["paper_tex"][:50]] or ["  - WARNING: no paper tex files"]
    report += ["- paper_docs:"]
    report += [f"  - {p}" for p in inputs_used["paper_docs"][:50]] or ["  - WARNING: No additional USER/paper docs found (.pdf/.md/.txt/.json)"]
    report += ["- notes:"]
    report += [f"  - {p}" for p in inputs_used["notes"][:50]] or ["  - WARNING: No USER/notes/ files found (.md/.tex/.txt)"]
    report += ["- references_for_seeds:"]
    report += [f"  - {p}" for p in inputs_used["references_for_seeds"][:50]] or ["  - WARNING: No USER/references/for_seeds/ directory or no supported files"]
    report += ["- references_general:"]
    report += [f"  - {p}" for p in inputs_used["references_general"][:50]] or ["  - WARNING: No additional USER/references files found"]
    report += ["- references:"]
    report += [f"  - {p}" for p in inputs_used["references"][:50]] or ["  - WARNING: No USER/references files found"]
    report += ["- bib:"]
    report += [f"  - {p}" for p in inputs_used["bib"][:50]] or ["  - WARNING: No bib files discovered"]
    report += ["- keywords_source:"]
    report += [f"  - {p}" for p in inputs_used["keywords_source"][:50]] or ["  - WARNING: No keyword source files found"]
    report += ["- references_checked:"]
    report += [f"  - {p}" for p in inputs_used["references_checked"][:50]] or ["  - WARNING: No references checked"]
    report += ["- seed_source_breakdown:"]
    ssb = inputs_used.get("seed_source_breakdown", {})
    if isinstance(ssb, dict):
        report += [
            f"  - for_seeds: {ssb.get('for_seeds', 0)}",
            f"  - bib: {ssb.get('bib', 0)}",
            f"  - references_pdf_general: {ssb.get('references_pdf_general', 0)}",
            f"  - notes_references: {ssb.get('notes_references', 0)}",
        ]

    report += [
        "",
        "## Field",
        f"- field: {field}",
        f"- field_confidence: {field_confidence}",
        f"- field_evidence_terms: {', '.join(field_evidence_terms) if field_evidence_terms else '(none)'}",
        "",
        "## Keywords",
        f"- top 20 keywords: {', '.join(keywords_capped[:20])}",
        f"- top 10 bigrams: {', '.join(bigrams[:10])}",
        "",
        "## Seed table",
        f"- Seeds: found {seed_found_count} candidates; emitted top K={SEED_TOP_K} ranked by relevance.",
        "- columns: title | first_author | arxiv_id | link | completeness",
    ]
    if seed_found_count < min_complete_seeds:
        report += [
            f"- Run completed with warnings: seeds found={seed_found_count} (<{min_complete_seeds}). Staged profile emitted."
        ]

    rows_for_report = seed_rows_for_output[:SEED_TOP_K]
    for s in rows_for_report:
        first_author = s.get("authors", ["UNKNOWN"])[0] if isinstance(s.get("authors"), list) and s.get("authors") else "UNKNOWN"
        arx = s.get("arxiv_id") if s.get("arxiv_id") else "null"
        report.append(f"- {s.get('title','')} | {first_author} | {arx} | {s.get('link','')} | {s.get('completeness','COMPLETE')}")

    report += [
        "",
        "## Status",
        f"- seed_summary: found={seed_summary['found']} ranked={seed_summary['ranked']} emitted={seed_summary['emitted']} min_required={seed_summary['min_required']} status={seed_summary['status']}",
        f"- keyword_quality_gate: {'met' if req_diag['has_keywords_good'] else 'warn'}",
        f"- field_detected: {'met' if req_diag['has_field'] else 'warn'}",
        "",
        "## Unresolved cites",
        f"- count: {len(unresolved_cites)}",
    ]
    if unresolved_cites:
        report.append(f"- keys: {', '.join(unresolved_cites)}")

    report += ["", "## Stage Breakdown"]
    for st in stage_breakdown:
        report.append(
            f"- {st['stage']} attempted={str(st['attempted']).lower()} added={st['added']} complete={st['complete_count']} partial={st['partial_count']}"
        )
        if st.get("top_missing_fields"):
            report.append(f"  - top_missing_fields: {', '.join(st['top_missing_fields'])}")

    if warnings:
        report += ["", "## Warnings"]
        report += [f"- {w}" for w in warnings]
    report += ["", "## Debug"]
    report += [f"- filtered_token_counts: {json.dumps(filtered_token_counts)}"]
    report += [f"- dropped_top_terms: {json.dumps(dropped_top_terms)}"]

    inputs_scanned = {
        "paths": {
            "paper_root": to_rel(root, user_paper),
            "notes_root": to_rel(root, user_notes),
            "references_root": to_rel(root, user_refs_for_seeds),
            "references_parent_root": to_rel(root, refs_root),
        },
        "found": {
            "tex_count": len(inputs_used["paper_tex"]),
            "bib_count": len(inputs_used["bib"]),
            "references_count": len(inputs_used["references_for_seeds"]),
            "references_extra_count": len(inputs_used["references_general"]),
            "references_total_count": len(inputs_used["references"]),
            "notes_count": len(inputs_used["notes"]),
        },
        "files": inputs_used,
    }
    resolved = {
        "task_id": task_id,
        "tex_files_count": len(inputs_used["paper_tex"]),
        "paper_docs_files_count": len(inputs_used["paper_docs"]),
        "notes_files_count": len(inputs_used["notes"]),
        "references_files_count": len(inputs_used["references_for_seeds"]),
        "references_extra_files_count": len(inputs_used["references_general"]),
        "references_all_files_count": len(inputs_used["references"]),
        "bib_files_count": len(inputs_used["bib"]),
        "cites_count": len(cite_keys),
        "unresolved_cites_count": len(unresolved_cites),
        "field": field,
        "field_confidence": field_confidence,
        "keywords_count": len(keywords),
        "seed_found_count": seed_found_count,
        "complete_seed_count": len(complete),
        "invalid_seed_count": len(invalid_rows),
        "partial_seed_count": len(partial),
        "online_requested": request_online_lookup,
        "net_allowed": net_allowed,
        "online_attempted": online_attempted,
        "online_backend_used": online_backend_used,
        "online_fail_reason": online_fail_reason,
        "validation_phase": "post_online",
        "online_failfast": online_failfast,
        "min_complete_seeds": min_complete_seeds,
        "attempts": attempts,
        "stage_breakdown": stage_breakdown,
        "requirements": {
            "ok": True,
            "missing": missing_requirements,
            "diagnostics": req_diag,
            "completeness_rules": "COMPLETE means title + (authors or link/arxiv_id/doi); abstract is optional",
        },
        "inputs_scanned": inputs_scanned,
        "next_actions": [
            "Add 3 papers into USER/references/for_seeds/ with title/authors/abstract/arxiv-or-doi-link",
            "Add a .bib under USER/paper/ (with abstracts if available)",
            "Enable online_lookup=true in request (or --online) to complete missing abstracts",
        ],
        "stop_reason": "Completed with warning-only policy; no hard content gates applied.",
        "timestamp_utc": now_utc(),
    }
    resolved_json.parent.mkdir(parents=True, exist_ok=True)
    resolved_json.write_text(json.dumps(resolved, indent=2), encoding="utf-8")

    validate_output_payload(payload)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    out_report.parent.mkdir(parents=True, exist_ok=True)
    out_report.write_text("\n".join(report) + "\n", encoding="utf-8")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--task-id", required=True)
    ap.add_argument("--request-path", required=True)
    ap.add_argument("--user-paper", required=True)
    ap.add_argument("--user-notes", required=True)
    ap.add_argument("--user-refs-for-seeds", required=True)
    ap.add_argument("--out-json", required=True)
    ap.add_argument("--out-report", required=True)
    ap.add_argument("--resolved-json", required=True)
    ap.add_argument("--online", action="store_true")
    args = ap.parse_args()

    try:
        return build_profile(
            root=Path(args.root).resolve(),
            task_id=args.task_id,
            request_path=Path(args.request_path).resolve(),
            user_paper=Path(args.user_paper).resolve(),
            user_notes=Path(args.user_notes).resolve(),
            user_refs_for_seeds=Path(args.user_refs_for_seeds).resolve(),
            out_json=Path(args.out_json).resolve(),
            out_report=Path(args.out_report).resolve(),
            resolved_json=Path(args.resolved_json).resolve(),
            online_lookup_cli=args.online,
        )
    except Exception as e:
        print(f"ERROR={e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
