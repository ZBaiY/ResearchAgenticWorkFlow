#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d /tmp/paper_seed_cap_XXXX)"
PAPER="$WORK/paper"
NOTES="$WORK/notes"
REFS="$WORK/references/for_seeds"
mkdir -p "$PAPER" "$NOTES" "$REFS"

cat > "$PAPER/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Seed cap regression paper}
\begin{abstract}
Neutrino oscillation phenomenology in ultralight dark matter backgrounds.
\end{abstract}
\bibliography{refs}
\cite{A2024,B2024,C2024,D2024,E2024}
\end{document}
EOF

cat > "$PAPER/refs.bib" <<'EOF'
@article{A2024,title={A seed title},author={Alpha One},year={2024},eprint={2401.00001},archivePrefix={arXiv}}
@article{B2024,title={B seed title},author={Beta Two},year={2024},eprint={2401.00002},archivePrefix={arXiv}}
@article{C2024,title={C seed title},author={Gamma Three},year={2024},eprint={2401.00003},archivePrefix={arXiv}}
@article{D2024,title={D seed title},author={Delta Four},year={2024},eprint={2401.00004},archivePrefix={arXiv}}
@article{E2024,title={E seed title},author={Epsilon Five},year={2024},eprint={2401.00005},archivePrefix={arXiv}}
@article{F2024,title={F seed title},author={Zeta Six},year={2024},eprint={2401.00006},archivePrefix={arXiv}}
@article{G2024,title={G seed title},author={Eta Seven},year={2024},eprint={2401.00007},archivePrefix={arXiv}}
@article{H2024,title={H seed title},author={Theta Eight},year={2024},eprint={2401.00008},archivePrefix={arXiv}}
@article{I2024,title={I seed title},author={Iota Nine},year={2024},eprint={2401.00009},archivePrefix={arXiv}}
@article{J2024,title={J seed title},author={Kappa Ten},year={2024},eprint={2401.00010},archivePrefix={arXiv}}
@article{K2024,title={K seed title},author={Lambda Eleven},year={2024},eprint={2401.00011},archivePrefix={arXiv}}
@article{L2024,title={L seed title},author={Mu Twelve},year={2024},eprint={2401.00012},archivePrefix={arXiv}}
EOF

cat > "$REFS/surrogate.pdf" <<'EOF'
PDF SURROGATE TITLE
Authors: Seed Author
arXiv: 2502.99991
EOF

REQ="AGENTS/requests/regression/paper_profile_seed_cap.md"
mkdir -p "$(dirname "$REQ")"
cat > "$REQ" <<'EOF'
# Request
Goal:
seed cap regression
online_lookup: false
EOF

TASK="test_paper_seed_cap_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK" --request "$REQ" >/tmp/paper_seed_cap_start.out
PAPER_PROFILE_USER_PAPER="$PAPER" PAPER_PROFILE_USER_NOTES="$NOTES" PAPER_PROFILE_USER_REFS_FOR_SEEDS="$REFS" \
./bin/agenthub run --task "$TASK" --yes >/tmp/paper_seed_cap_run.out

python3 - <<PY
import json
from pathlib import Path
t = "$TASK"
p = json.loads(Path(f"AGENTS/tasks/{t}/outputs/paper_profile/paper_profile.json").read_text())
seeds = p["profile"]["seed_papers"]
assert len(seeds) <= 5, len(seeds)
assert p["profile"]["seed_summary"]["found"] >= 3, p["profile"]["seed_summary"]
print("PASS seed cap/regression", t, "seeds=", len(seeds))
PY

echo "PASS: paper_profile seed cap regression checks passed"
