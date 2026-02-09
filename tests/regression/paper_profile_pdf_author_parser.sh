#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import tempfile
from pathlib import Path

from AGENTS.skills.paper_profile_update.scripts.build_profile import (
    discover_reference_candidates,
    is_author_line,
    parse_pdf_first_page_metadata,
)

sample_lines = [
    "Parametric resonance in neutrino oscillations induced by",
    "ultra-light dark matter: implications for KamLAND",
    "Gilad Perez, Yotam Soreq, Tomer Volansky",
    "Abstract",
    "We study ...",
]
sample_text = "\n".join(sample_lines)

assert is_author_line(sample_lines[1]) is False, "subtitle line must not be classified as authors"
assert is_author_line(sample_lines[2]) is True, "name line should be author-like"

meta, evidence = parse_pdf_first_page_metadata(sample_text)
title = meta.get("title", "")
authors = meta.get("authors", [])

assert "Parametric resonance in neutrino oscillations induced by ultra-light dark matter implications for KamLAND" in title
assert isinstance(authors, list) and len(authors) >= 1
assert not any("implications for KamLAND" in a for a in authors), authors
assert evidence.get("method") == "pdf_first_page_rules"
assert len(evidence.get("title_lines", [])) >= 2
assert len(evidence.get("author_lines", [])) >= 1

with tempfile.TemporaryDirectory(prefix="pdf_author_reg_") as td:
    p = Path(td) / "bad_author_parse.pdf"
    p.write_text(sample_text, encoding="utf-8")
    warnings = []
    refs = discover_reference_candidates(Path(td), warnings, label="USER/references/for_seeds")
    assert len(refs) == 1
    rc = refs[0]
    assert "implications for KamLAND" not in " | ".join(rc.authors), rc.authors
    assert rc.title.lower().startswith("parametric resonance in neutrino oscillations induced by")
    assert isinstance(rc.extraction_evidence, dict) and rc.extraction_evidence.get("method") == "pdf_first_page_rules"

print("PASS: pdf author/title parsing regression")
PY
