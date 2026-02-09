#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

WORKDIR="$(mktemp -d /tmp/paper_profile_contract_XXXX)"
PAPER_DIR="$WORKDIR/paper"
NOTES_DIR="$WORKDIR/notes"
REFS_DIR="$WORKDIR/references/for_seeds"
mkdir -p "$PAPER_DIR" "$NOTES_DIR" "$REFS_DIR"

cat > "$PAPER_DIR/main.tex" <<'EOF'
\documentclass{article}
\title{Neutrino oscillations from ultralight dark matter couplings}
\begin{document}
\maketitle
\begin{abstract}
We study neutrino flavor oscillation in ultralight dark matter backgrounds and constrain coupling scales.
\end{abstract}
\keywords{neutrino oscillation, ultralight dark matter, flavor conversion}
\input{sec1}
\bibliography{references}
\end{document}
EOF

cat > "$PAPER_DIR/sec1.tex" <<'EOF'
\newcommand{\vect}[1]{\mathbf{#1}}
The oscillation Hamiltonian is discussed in detail and we cite \cite{Smith2024,Doe2023}.
\begin{equation}
H = \frac{\Delta m^2}{2E}
\end{equation}
EOF

cat > "$PAPER_DIR/references.bib" <<'EOF'
@article{Smith2024,
  title={Ultralight dark matter effects in neutrino oscillations},
  author={Smith, Alice},
  year={2024},
  doi={10.1000/smith2024},
  abstract={Ultralight dark matter effects modify neutrino oscillation probabilities.},
  eprint={2401.12345},
  archivePrefix={arXiv}
}
@article{Doe2023,
  title={Flavor conversion constraints from long-baseline data},
  author={Doe, Carol},
  year={2023},
  abstract={Long-baseline data constrains flavor conversion signatures in new physics scenarios.},
  eprint={2302.11111},
  archivePrefix={arXiv}
}
@article{Roe2022,
  title={Neutrino mixing and dark-sector induced phases},
  author={Roe, Dan},
  year={2022},
  abstract={Dark-sector induced phases alter neutrino mixing and propagation.},
  eprint={2201.12345},
  archivePrefix={arXiv}
}
EOF

cat > "$NOTES_DIR/idea.md" <<'EOF'
Focus on neutrino flavor conversion phenomenology in dark matter backgrounds.
EOF

cat > "$REFS_DIR/ref_a.txt" <<'EOF'
Ultralight dark matter and neutrino oscillation signatures
Authors: Alice Smith
Abstract: Ultralight dark matter and neutrino oscillation signatures in long-baseline data.
DOI: 10.1000/smith2024
EOF

cat > "$REFS_DIR/ref_b.txt" <<'EOF'
Long-baseline flavor conversion constraints from precision neutrino data
Authors: Carol Doe
Abstract: Precision neutrino data constrains flavor conversion and dark-sector interactions.
EOF

cat > "$REFS_DIR/ref_c.txt" <<'EOF'
Dark-sector induced phases in neutrino propagation
Authors: Dan Roe
Abstract: Dark-sector induced phases modify neutrino propagation and oscillation signatures.
arXiv:2201.12345
EOF

REQ="AGENTS/requests/regression/paper_profile_contract.md"
mkdir -p "$(dirname "$REQ")"
cat > "$REQ" <<'EOF'
# Request
Goal:
Build high-quality profile
EOF

TASK="test_paper_profile_contract_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK" --request "$REQ" >/tmp/paper_profile_contract_start.out
PAPER_PROFILE_USER_PAPER="$PAPER_DIR" \
PAPER_PROFILE_USER_NOTES="$NOTES_DIR" \
PAPER_PROFILE_USER_REFS_FOR_SEEDS="$REFS_DIR" \
./bin/agenthub run --task "$TASK" --yes >/tmp/paper_profile_contract_run.out

python3 - <<PY
import json
from pathlib import Path

task = "$TASK"
p = json.loads(Path(f"AGENTS/tasks/{task}/outputs/paper_profile/paper_profile.json").read_text())
report = Path(f"AGENTS/tasks/{task}/review/paper_profile_update_report.md").read_text()

# source groups exist
for g in ["tex", "bib", "references_for_seeds", "references_general"]:
    assert g in p["source_files"], g

# field detection
assert p["profile"].get("field", "").strip() != ""
assert float(p["profile"].get("field_confidence", 0.0)) >= 0.0
assert isinstance(p["profile"].get("field_evidence_terms", []), list)

# keywords no junk
kw = [x.lower() for x in p["profile"]["keywords"]]
for bad in ["begin", "end", "newcommand", "equation", "label", "ref"]:
    assert bad not in kw, bad
assert len(kw) >= 12, len(kw)

# seeds
assert len(p["profile"]["seed_papers"]) >= 3, len(p["profile"]["seed_papers"])
assert len(p["profile"]["seed_papers"]) <= 5, len(p["profile"]["seed_papers"])

# report grouping
for marker in ["- paper_tex:", "- notes:", "- references_for_seeds:", "- references:", "- bib:"]:
    assert marker in report, marker

print("PASS: regression contract verified", task)
PY
