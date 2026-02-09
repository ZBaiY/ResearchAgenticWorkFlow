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
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Set, Tuple

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
SEED_TOP_K = 10
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


def discover_reference_candidates(ref_root: Path, warnings: List[str]) -> List[RefCandidate]:
    if not ref_root.exists():
        warnings.append("No USER/references/for_seeds/ directory or no files found")
        return []

    files = sorted([p for p in ref_root.rglob("*") if p.is_file()])
    ref_files = [p for p in files if p.suffix.lower() in {".pdf", ".txt", ".md", ".json"}]
    if not ref_files:
        warnings.append("No reference files (.pdf/.txt/.md/.json) found under USER/references/for_seeds/")
        return []

    out: List[RefCandidate] = []
    for p in ref_files:
        suffix = p.suffix.lower()
        meta: Dict[str, object] = {}
        blob = ""
        cap_tokens: Set[str] = set()

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
                    meta = parse_metadata_from_text(blob)
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
    has_seeds = complete_seed_count >= MIN_COMPLETE_SEEDS

    missing: List[str] = []
    if not has_field:
        missing.append("field")
    if not has_keywords_good:
        missing.append("keywords(quality_gate)")
    if not has_seeds:
        missing.append(f"seed_papers(complete>={MIN_COMPLETE_SEEDS})")

    diagnostics = {
        "has_field": has_field,
        "has_keywords_good": has_keywords_good,
        "complete_seed_count": complete_seed_count,
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


def validate_seed(seed: Dict[str, object], warnings: List[str]) -> Tuple[bool, List[str]]:
    missing: List[str] = []
    title = str(seed.get("title", "") or "").strip()
    if not title:
        missing.append("title")
    authors = seed.get("authors")
    if not isinstance(authors, list) or len([a for a in authors if str(a).strip()]) < 1:
        missing.append("authors")
    abstract = str(seed.get("abstract", "") or "").strip()
    if not abstract:
        missing.append("abstract")
    link = str(seed.get("link", "") or "").strip()
    if not link or not URL_RE.match(link):
        missing.append("link")
    arxiv_id = seed.get("arxiv_id")
    if arxiv_id is not None and str(arxiv_id).strip() == "":
        seed["arxiv_id"] = None
    if seed.get("arxiv_id") is None and ("abstract" in missing or "link" in missing):
        if "arxiv_id" not in missing:
            missing.append("arxiv_id_or_link_abstract")

    if "authors" in missing:
        seed["authors"] = ["UNKNOWN"]
        warnings.append(f"seed_authors_unknown:{title or seed.get('source_path','unknown')}")
        missing = [m for m in missing if m != "authors"]

    return len(missing) == 0, missing


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


def try_complete_online(seeds: List[Dict[str, object]], cache_dir: Path) -> List[Dict[str, object]]:
    cache_dir.mkdir(parents=True, exist_ok=True)
    out: List[Dict[str, object]] = []
    for s in seeds:
        row = dict(s)
        need_abstract = not str(row.get("abstract", "") or "").strip()
        need_link = not str(row.get("link", "") or "").strip()
        if not (need_abstract or need_link):
            out.append(row)
            continue
        arxiv_id = str(row.get("arxiv_id", "") or "").strip()
        if not arxiv_id:
            out.append(row)
            continue
        cache_key = re.sub(r"[^a-zA-Z0-9_.-]", "_", arxiv_id)
        cache_path = cache_dir / f"{cache_key}.json"
        try:
            if cache_path.exists():
                meta = json.loads(cache_path.read_text(encoding="utf-8"))
            else:
                meta = arxiv_lookup(arxiv_id)
                cache_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")
        except Exception as e:
            raise RuntimeError(f"NETWORK_LOOKUP_FAILED cause={e} hint=Disable online_lookup or retry later")
        if meta.get("title") and not row.get("title"):
            row["title"] = meta["title"]
        if meta.get("abstract") and not row.get("abstract"):
            row["abstract"] = meta["abstract"]
        if meta.get("authors") and (not isinstance(row.get("authors"), list) or not row.get("authors")):
            row["authors"] = meta["authors"]
        if meta.get("year") and not row.get("year"):
            row["year"] = meta["year"]
        if meta.get("link") and not row.get("link"):
            row["link"] = meta["link"]
        out.append(row)
    return out


def parse_online_flag(request_text: str, env_online: bool, cli_online: bool) -> bool:
    if cli_online:
        return True
    if env_online:
        return True
    if re.search(r"online_lookup\s*:\s*true", request_text, flags=re.I):
        return True
    if re.search(r"request\.flags\.online_lookup\s*:\s*true", request_text, flags=re.I):
        return True
    return False


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

    request_text = slurp(request_path)
    online_lookup = parse_online_flag(
        request_text=request_text,
        env_online=str(os.environ.get("ONLINE_LOOKUP", "0")).lower() in {"1", "true", "yes"},
        cli_online=online_lookup_cli,
    )

    tex_candidates = sorted([p for p in user_paper.rglob("*.tex") if p.is_file()])
    if not tex_candidates:
        raise RuntimeError("No TeX sources found under USER/paper.")

    main_tex = choose_main_tex(tex_candidates)
    tex_files = expand_tex_graph(main_tex)
    if not tex_files:
        raise RuntimeError("No TeX sources found after include resolution.")

    bib_files = discover_bib_files(tex_files, user_paper)
    note_files = discover_notes(user_notes)
    ref_candidates = discover_reference_candidates(user_refs_for_seeds, warnings)
    cite_keys = collect_cite_keys(tex_files)
    cite_set = set(cite_keys)
    structured_phrases = extract_structured_phrases(tex_files)

    all_tex_text = "\n".join(slurp(p) for p in tex_files)
    blocks = extract_blocks(slurp(main_tex))
    title = blocks.get("title", "")
    abstract = blocks.get("abstract", "")
    intro = blocks.get("introduction", "")
    blocks_for_ngrams = [x for x in [title, abstract, intro] if x.strip()] or [clean_latex_text(all_tex_text)]

    bib_entries: List[BibEntry] = []
    for b in bib_files:
        try:
            bib_entries.extend(parse_bib_entries(slurp(b), source_path=to_rel(root, b)))
        except Exception as e:
            warnings.append(f"bib_parse_failed:{to_rel(root,b)}:{e}")

    unresolved_cites = [k for k in cite_keys if k not in {e.bibkey for e in bib_entries}]

    author_name_set: Set[str] = set()
    for e in bib_entries:
        author_name_set |= author_name_tokens_from_authors(parse_authors(e.fields.get("author", "")))
    for r in ref_candidates:
        author_name_set |= author_name_tokens_from_authors(r.authors)
    ref_cap_tokens: Set[str] = set()
    for r in ref_candidates:
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
    for r in ref_candidates:
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
        for r in ref_candidates:
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

    # Build seed candidates
    kw_weights = dict(unigram_map)
    for p in bigrams[:TOP_K_BIGRAMS]:
        for t in p.split():
            kw_weights[t] = kw_weights.get(t, 0.0) + 0.4
    for p in trigrams[:TOP_K_TRIGRAMS]:
        for t in p.split():
            kw_weights[t] = kw_weights.get(t, 0.0) + 0.5

    seed_candidates: List[Dict[str, object]] = []

    # references first
    for rc in ref_candidates:
        rtoks = set(tokenize(rc.title + " " + rc.abstract + " " + rc.text))
        matched = [t for t in sorted(rtoks) if t in kw_weights]
        score = sum(kw_weights.get(t, 0.0) for t in matched) + 3.0
        link = rc.link or (f"https://arxiv.org/abs/{rc.arxiv_id}" if rc.arxiv_id else "")
        seed_candidates.append({
            "title": rc.title,
            "authors": rc.authors,
            "arxiv_id": rc.arxiv_id or None,
            "abstract": rc.abstract,
            "link": link,
            "year": int(rc.year) if rc.year.isdigit() else None,
            "doi": rc.doi or None,
            "source": {"kind": "references", "path": rc.source_path},
            "source_path": rc.source_path,
            "why": matched[:8],
            "cited": False,
            "_score": score,
        })

    # bib second
    for e in bib_entries:
        title_b = e.fields.get("title", "")
        authors = parse_authors(e.fields.get("author", ""))
        arxiv_id = ""
        if (e.fields.get("archiveprefix", "").lower() == "arxiv" and e.fields.get("eprint")) or e.fields.get("eprint"):
            arxiv_id = e.fields.get("eprint", "")
        m_arx = ARXIV_ID_RE.search(arxiv_id)
        if m_arx:
            arxiv_id = m_arx.group(1)
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
        score = sum(kw_weights.get(t, 0.0) for t in matched) + (2.0 if e.bibkey in cite_set else 0.0)
        year_val = int(e.fields.get("year")) if str(e.fields.get("year", "")).isdigit() else None
        seed_candidates.append({
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
            "_score": score,
        })

    # dedup and sort by priority + score
    # priority: references first (kind weight)
    for s in seed_candidates:
        kind = s.get("source", {}).get("kind", "") if isinstance(s.get("source"), dict) else ""
        s["_priority"] = 0 if kind == "references" else 1

    seed_candidates.sort(key=lambda x: (int(x.get("_priority", 9)), -float(x.get("_score", 0.0)), str(x.get("title", ""))))
    deduped: List[Dict[str, object]] = []
    seen_keys: Set[str] = set()
    for s in seed_candidates:
        key = canonical_seed_key(s)
        if key in seen_keys:
            continue
        seen_keys.add(key)
        deduped.append(s)

    if online_lookup:
        attempts.append("online_lookup:complete_partial_seeds")
        deduped = try_complete_online(deduped, cache_dir=root / "AGENTS" / "cache" / "online_meta")

    complete: List[Dict[str, object]] = []
    invalid_rows: List[Dict[str, object]] = []
    for s in deduped:
        ok, missing = validate_seed(s, warnings)
        row = dict(s)
        row["completeness"] = "COMPLETE" if ok else f"INVALID({','.join(missing)})"
        if ok:
            row.pop("_score", None)
            row.pop("_priority", None)
            row["source_path"] = row.get("source", {}).get("path", row.get("source_path", "")) if isinstance(row.get("source"), dict) else row.get("source_path", "")
            complete.append(row)
        else:
            invalid_rows.append(row)

    if len(complete) < MIN_COMPLETE_SEEDS:
        warnings.append(
            f"seeds_minimum_failed:complete={len(complete)}<required={MIN_COMPLETE_SEEDS};attempts={';'.join(attempts)}"
        )

    categories = ["hep-ph", "manuscript"] if any(t in corpus_tokens for t in {"neutrino", "dark", "matter", "uldm", "flavor"}) else ["physics", "manuscript"]
    short_blurb = first_sentence(abstract) or first_sentence(intro) or "Local manuscript profile generated from USER content."
    themes = dedup_keep_order((trigrams + bigrams)[:6]) or ["manuscript_overview", "method_summary", "related_work"]

    inputs_used = {
        "paper_tex": [to_rel(root, p) for p in tex_files],
        "notes": [to_rel(root, p) for p in note_files],
        "references": [to_rel(root, Path(r.source_path)) if str(r.source_path).startswith(str(root)) else r.source_path for r in ref_candidates],
        "bib": [to_rel(root, p) for p in bib_files],
    }

    if not inputs_used["notes"]:
        warnings.append("No USER/notes/ files found (.md/.tex/.txt)")
    if not inputs_used["references"]:
        warnings.append("No USER/references/for_seeds/ directory or no supported files")
    if not inputs_used["bib"]:
        warnings.append("No .bib files discovered from tex directives or fallback search")

    profile = {
        "field": field,
        "field_confidence": field_confidence,
        "field_evidence_terms": field_evidence_terms,
        "keywords": keywords,
        "bigrams": bigrams,
        "trigrams": trigrams,
        "structured_phrases": structured_phrases,
        "categories": categories,
        "short_blurb": short_blurb,
        "related_work_themes": themes,
        "seed_papers": complete[:SEED_TOP_K],
        "unresolved_cites": unresolved_cites,
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

    requirements_met, missing_requirements, req_diag = evaluate_requirements(
        keywords=keywords,
        bigrams=bigrams,
        trigrams=trigrams,
        field=field,
        field_confidence=field_confidence,
        complete_seed_count=len(complete),
    )

    payload = {
        "task_id": task_id,
        "generated_at_utc": now_utc(),
        "source_files": {
            "tex": inputs_used["paper_tex"],
            "bib": inputs_used["bib"],
        },
        "inputs_used": inputs_used,
        "extraction": {
            "stopwords_version": "paper_profile_v5",
            "hard_stopwords_enabled": True,
            "filtered_token_counts": filtered_token_counts,
            "dropped_top_terms": dropped_top_terms,
            "df_ratio_max": DF_RATIO_MAX,
            "df_min": DF_MIN,
            "top_k_keywords": TOP_K_KEYWORDS,
            "top_k_bigrams": TOP_K_BIGRAMS,
            "top_k_trigrams": TOP_K_TRIGRAMS,
        },
        "profile": profile,
        "notes": warnings,
    }

    report = [
        "# paper_profile_update Report",
        "",
        f"- task_id: {task_id}",
        "- skill: paper_profile_update",
        f"- output_profile: {to_rel(root, out_json)}",
        f"- online_lookup: {str(online_lookup).lower()}",
        "",
        "## Inputs used",
        "- keywords source(s):",
        "  - paper_tex + notes + references + bib",
        "- field/domain source(s):",
        "  - paper_tex (+ notes support)",
        "- seed source(s):",
        "  - references first, then cited bib, then relevant bib",
        "- paper_tex:",
    ]
    report += [f"  - {p}" for p in inputs_used["paper_tex"][:50]] or ["  - WARNING: no paper tex files"]
    report += ["- notes:"]
    report += [f"  - {p}" for p in inputs_used["notes"][:50]] or ["  - WARNING: No USER/notes/ files found (.md/.tex/.txt)"]
    report += ["- references:"]
    report += [f"  - {p}" for p in inputs_used["references"][:50]] or ["  - WARNING: No USER/references/for_seeds/ directory or no supported files"]
    report += ["- bib:"]
    report += [f"  - {p}" for p in inputs_used["bib"][:50]] or ["  - WARNING: No bib files discovered"]

    report += [
        "",
        "## Field",
        f"- field: {field}",
        f"- field_confidence: {field_confidence}",
        f"- field_evidence_terms: {', '.join(field_evidence_terms) if field_evidence_terms else '(none)'}",
        "",
        "## Keywords",
        f"- top 20 keywords: {', '.join(keywords[:20])}",
        f"- top 10 bigrams: {', '.join(bigrams[:10])}",
        "",
        "## Seed table",
        "- columns: title | first_author | arxiv_id | link | completeness",
    ]

    rows_for_report = complete[:5] + invalid_rows[:5]
    for s in rows_for_report:
        first_author = s.get("authors", ["UNKNOWN"])[0] if isinstance(s.get("authors"), list) and s.get("authors") else "UNKNOWN"
        arx = s.get("arxiv_id") if s.get("arxiv_id") else "null"
        report.append(f"- {s.get('title','')} | {first_author} | {arx} | {s.get('link','')} | {s.get('completeness','COMPLETE')}")

    report += [
        "",
        f"## Unresolved cites",
        f"- count: {len(unresolved_cites)}",
    ]
    if unresolved_cites:
        report.append(f"- keys: {', '.join(unresolved_cites)}")

    report += [
        "",
        "## Requirements",
        f"- complete_seed_minimum({MIN_COMPLETE_SEEDS}): {'met' if req_diag['complete_seed_count'] >= MIN_COMPLETE_SEEDS else 'NOT_MET'}",
        f"- keyword_quality_gate: {'met' if req_diag['has_keywords_good'] else 'NOT_MET'}",
        f"- field_detected: {'met' if req_diag['has_field'] else 'NOT_MET'}",
        f"- overall: {'met' if requirements_met else 'NOT_MET'}",
    ]

    if warnings:
        report += ["", "## Warnings"]
        report += [f"- {w}" for w in warnings]

    inputs_scanned = {
        "paths": {
            "paper_root": to_rel(root, user_paper),
            "notes_root": to_rel(root, user_notes),
            "references_root": to_rel(root, user_refs_for_seeds),
        },
        "found": {
            "tex_count": len(inputs_used["paper_tex"]),
            "bib_count": len(inputs_used["bib"]),
            "references_count": len(inputs_used["references"]),
            "notes_count": len(inputs_used["notes"]),
        },
        "files": inputs_used,
    }
    resolved = {
        "task_id": task_id,
        "tex_files_count": len(inputs_used["paper_tex"]),
        "notes_files_count": len(inputs_used["notes"]),
        "references_files_count": len(inputs_used["references"]),
        "bib_files_count": len(inputs_used["bib"]),
        "cites_count": len(cite_keys),
        "unresolved_cites_count": len(unresolved_cites),
        "field": field,
        "field_confidence": field_confidence,
        "keywords_count": len(keywords),
        "complete_seed_count": len(complete),
        "invalid_seed_count": len(invalid_rows),
        "online_lookup": online_lookup,
        "attempts": attempts,
        "requirements": {
            "ok": requirements_met,
            "missing": missing_requirements,
            "diagnostics": req_diag,
            "completeness_rules": "seed counts only if abstract present and required fields are complete",
        },
        "inputs_scanned": inputs_scanned,
        "next_actions": [
            "Add USER/references/for_seeds documents (PDF/text with title/authors/abstract) or USER/paper/*.bib with abstracts",
            "Set online_lookup=true in request (or --online) to complete missing abstracts from arXiv metadata",
            "Specify main TeX path explicitly by ensuring USER/paper/main.tex or a TeX file with \\documentclass/\\begin{document}",
        ],
        "stop_reason": "Stopped early to avoid spending tokens/time on incomplete low-quality profile output.",
        "timestamp_utc": now_utc(),
    }
    resolved_json.parent.mkdir(parents=True, exist_ok=True)
    resolved_json.write_text(json.dumps(resolved, indent=2), encoding="utf-8")

    if not requirements_met:
        print("ERROR_CODE=PROFILE_REQUIREMENTS_NOT_MET", file=sys.stderr)
        print(f"MISSING={','.join(missing_requirements)}", file=sys.stderr)
        print(
            "COMPLETENESS_RULE=seed counts only if abstract present and required fields are complete",
            file=sys.stderr,
        )
        print(f"ONLINE_LOOKUP={str(online_lookup).lower()}", file=sys.stderr)
        print(
            "INPUTS_SCANNED="
            f"tex={inputs_scanned['found']['tex_count']},"
            f"bib={inputs_scanned['found']['bib_count']},"
            f"references={inputs_scanned['found']['references_count']},"
            f"notes={inputs_scanned['found']['notes_count']}",
            file=sys.stderr,
        )
        print("NEXT_ACTIONS=add references/bib with abstracts or enable online_lookup=true", file=sys.stderr)
        print("STOP_REASON=token/time saving; no partial profile emitted", file=sys.stderr)
        raise RuntimeError("PROFILE_REQUIREMENTS_NOT_MET")

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
