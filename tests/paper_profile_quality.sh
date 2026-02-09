#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkpaper() {
  local dir="$1"
  local missing="$2"
  mkdir -p "$dir"
  cat > "$dir/main.tex" <<'EOF'
\\documentclass{article}
\\usepackage{natbib}
\\title{Neutrino oscillations in ultralight dark matter backgrounds}
\\begin{document}
\\maketitle
\\begin{abstract}
We study neutrino flavor conversion in ultralight dark matter backgrounds and derive phenomenological constraints.
\\end{abstract}
\\keywords{neutrino oscillation, ultralight dark matter}
\\input{sec1}
\\bibliography{references}
\\end{document}
EOF

  if [[ "$missing" == "yes" ]]; then
    cat > "$dir/sec1.tex" <<'EOF'
\\newcommand{\\vect}[1]{\\mathbf{#1}}
In this section we discuss the oscillation Hamiltonian and compare with data.\\
We cite key studies \\cite{Smith2024,Missing2025} and present sensitivity projections.
\\begin{equation}
H = \\frac{\\Delta m^2}{2E}
\\end{equation}
EOF
  else
    cat > "$dir/sec1.tex" <<'EOF'
\\newcommand{\\vect}[1]{\\mathbf{#1}}
In this section we discuss the oscillation Hamiltonian and compare with data.\\
We cite key studies \\cite{Smith2024,Doe2023} and present sensitivity projections.
\\begin{equation}
H = \\frac{\\Delta m^2}{2E}
\\end{equation}
EOF
  fi

  cat > "$dir/references.bib" <<'EOF'
@article{Smith2024,
  title={Ultralight dark matter effects in neutrino oscillations},
  author={Smith, Alice and Lee, Bob},
  year={2024},
  doi={10.1000/smith2024},
  eprint={2401.12345},
  archivePrefix={arXiv},
  primaryClass={hep-ph}
}

@article{Doe2023,
  title={Flavor conversion constraints from long-baseline neutrino data},
  author={Doe, Carol},
  year={2023},
  doi={10.1000/doe2023}
}
EOF
}

run_case() {
  local tag="$1"
  local missing="$2"
  local paper_dir
  paper_dir="$(mktemp -d "/tmp/paper_profile_${tag}_XXXX")"
  local refs_dir
  refs_dir="$(mktemp -d "/tmp/paper_profile_refs_${tag}_XXXX")"
  mkpaper "$paper_dir" "$missing"
  cat > "$refs_dir/ref1.txt" <<'EOF'
Ultralight dark matter effects in neutrino oscillations
Authors: Alice Smith
Abstract: We analyze ultralight dark matter effects in neutrino oscillations.
arXiv:2406.11111
EOF
  cat > "$refs_dir/ref2.txt" <<'EOF'
Flavor conversion constraints from long-baseline neutrino data
Authors: Carol Doe
Abstract: Long-baseline data constrains flavor conversion and dark-sector effects.
arXiv:2406.22222
EOF
  cat > "$refs_dir/ref3.txt" <<'EOF'
Neutrino propagation with dark-sector induced phases
Authors: Dan Roe
Abstract: Dark-sector phases modify neutrino propagation and oscillation patterns.
arXiv:2406.33333
EOF
  cat > "$refs_dir/structured_ref.md" <<'EOF'
title: Structured metadata entry for neutrino oscillations
authors: Alice Smith; Bob Doe
arxiv: 2406.44444
abstract: This structured entry describes oscillation phenomenology in dark-sector channels.
keywords: neutrino oscillation; ultralight dark matter
note: keep semantic fields only
EOF

  local req="AGENTS/requests/paper_profile_test_${tag}.md"
  cat > "$req" <<'EOF'
# Request
Goal:
build profile from local tex/bib
EOF

  local task="test_profile_quality_${tag}_$(date -u +%Y%m%dT%H%M%SZ)"
  ./bin/agenthub start --skill paper_profile_update --task-name "$task" --request "$req" >/tmp/paper_profile_start_${tag}.out
  PAPER_PROFILE_USER_PAPER="$paper_dir" PAPER_PROFILE_USER_REFS_FOR_SEEDS="$refs_dir" ./bin/agenthub run --task "$task" --yes >/tmp/paper_profile_run_${tag}.out

  python3 - <<PY
import json
from pathlib import Path

task = "$task"
profile = json.loads(Path(f"AGENTS/tasks/{task}/outputs/paper_profile/paper_profile.json").read_text())
kw = [x.lower() for x in profile["profile"]["keywords"]]
for bad in ["begin", "newcommand", "equation", "abstract", "authors", "arxiv", "alice", "bob", "carol", "doe", "smith"]:
    assert bad not in kw, f"bad keyword leaked: {bad}"
assert len(profile["profile"]["seed_papers"]) >= 1, "expected at least one seed paper"
assert len(profile["profile"]["seed_papers"]) >= 3, "expected >=3 ranked seed papers"
assert len(profile["profile"]["seed_papers"]) <= 5, "expected seed cap <=5"
for s in profile["profile"]["seed_papers"]:
    assert str(s.get("title", "")).strip(), "seed missing title"
    assert isinstance(s.get("authors", []), list) and len(s.get("authors", [])) >= 1, "seed missing authors"
    assert str(s.get("completeness", "")).strip() in {"COMPLETE", "PARTIAL", "INVALID"}, "seed completeness missing"
assert profile["profile"].get("field", "").strip(), "missing field"
assert float(profile["profile"].get("field_confidence", 0.0)) >= 0.0
assert "source_files" in profile
for grp in ["tex", "bib", "references_for_seeds", "references_general"]:
    assert grp in profile["source_files"], grp
assert "seed_summary" in profile["profile"]
assert profile["profile"]["seed_summary"]["found"] >= len(profile["profile"]["seed_papers"])

print("OK", task)
PY
}

echo "[1/2] cited entries resolved"
run_case "resolved" "no"

echo "[2/2] missing cite detection"
run_case "missing" "yes"

echo "PASS: paper_profile_update quality regression checks passed"
