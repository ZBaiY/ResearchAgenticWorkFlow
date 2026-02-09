#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

run_case() {
  local tag="$1"
  local req="$2"
  local paper="$3"
  local notes="$4"
  local refs="$5"
  local expect_rc="$6"

  local task="test_paper_profile_progressive_${tag}_$(date -u +%Y%m%dT%H%M%SZ)"
  ./bin/agenthub start --skill paper_profile_update --task-name "$task" --request "$req" >/tmp/paper_profile_progressive_start_${tag}.out
  set +e
  PAPER_PROFILE_USER_PAPER="$paper" \
  PAPER_PROFILE_USER_NOTES="$notes" \
  PAPER_PROFILE_USER_REFS_FOR_SEEDS="$refs" \
  ./bin/agenthub run --task "$task" --yes >/tmp/paper_profile_progressive_run_${tag}.out 2>/tmp/paper_profile_progressive_run_${tag}.err
  local rc=$?
  set -e
  if [[ "$expect_rc" == "0" && "$rc" -ne 0 ]]; then
    echo "FAIL: expected success for $tag rc=$rc" >&2
    cat /tmp/paper_profile_progressive_run_${tag}.err >&2 || true
    exit 1
  fi
  if [[ "$expect_rc" != "0" && "$rc" -eq 0 ]]; then
    echo "FAIL: expected failure for $tag" >&2
    exit 1
  fi
  echo "$task"
}

echo "[1/3] S0 only: for_seeds has >=3 complete seeds (pass, no online)"
W1="$(mktemp -d /tmp/paper_progressive_s0_XXXX)"
mkdir -p "$W1/paper" "$W1/notes" "$W1/references/for_seeds"
cat > "$W1/paper/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{ULDM neutrino manuscript}
\begin{abstract}
Neutrino flavor conversion in ultralight dark matter backgrounds with oscillation phenomenology, baseline effects, and coupling constraints.
\end{abstract}
\section{Introduction}
We study neutrino oscillation Hamiltonian, matter potential, dark-sector coupling, resonance behavior, and parameter inference.
\section{Methods}
We evaluate likelihood, posterior constraints, and robustness checks across benchmark scenarios.
\end{document}
EOF
cat > "$W1/notes/context.md" <<'EOF'
Keywords: neutrino oscillation, flavor conversion, ultralight dark matter, phenomenology, coupling constraints, baseline sensitivity.
EOF
for i in 1 2 3; do
  cat > "$W1/references/for_seeds/seed${i}.txt" <<EOF
Title: Seed $i neutrino dark matter
Authors: Author $i
Abstract: Complete abstract $i on neutrino oscillation and dark matter coupling.
arXiv: 2501.10${i}01
EOF
done
REQ1="AGENTS/requests/regression/paper_profile_progressive_s0.md"
mkdir -p "$(dirname "$REQ1")"
cat > "$REQ1" <<'EOF'
goal: progressive fallback s0
online_lookup: false
online_failfast: true
min_complete_seeds: 3
EOF
TASK1="$(run_case "s0" "$REQ1" "$W1/paper" "$W1/notes" "$W1/references/for_seeds" "0")"
python3 - <<PY
import json
from pathlib import Path
t = "$TASK1"
p = json.loads(Path(f"AGENTS/tasks/{t}/outputs/paper_profile/paper_profile.json").read_text())
complete = [s for s in p["profile"]["seed_papers"] if s.get("completeness") == "COMPLETE"]
assert len(complete) >= 3, len(complete)
print("OK S0 pass", t)
PY

echo "[2/3] S1/S4: bib-only no abstracts -> draft offline, pass online with mocked metadata"
W2="$(mktemp -d /tmp/paper_progressive_s1_XXXX)"
mkdir -p "$W2/paper" "$W2/notes" "$W2/references/for_seeds"
cat > "$W2/paper/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Bib fallback manuscript}
\begin{abstract}
Phenomenology of flavor conversion with ultralight dark matter interactions and oscillation constraints.
\end{abstract}
\section{Introduction}
We discuss neutrino propagation, effective Hamiltonian, baseline analyses, and parameter inference in dark-sector models.
\bibliography{refs}
\cite{A2024,B2024,C2024}
\end{document}
EOF
cat > "$W2/notes/context.txt" <<'EOF'
Domain terms: neutrino phenomenology, dark matter coupling, long-baseline oscillation analysis, flavor transition probabilities.
EOF
cat > "$W2/paper/refs.bib" <<'EOF'
@article{A2024,title={A title},author={Alpha, One},year={2024},eprint={2502.10001},archivePrefix={arXiv}}
@article{B2024,title={B title},author={Beta, Two},year={2024},eprint={2502.10002},archivePrefix={arXiv}}
@article{C2024,title={C title},author={Gamma, Three},year={2024},eprint={2502.10003},archivePrefix={arXiv}}
EOF
REQ2A="AGENTS/requests/regression/paper_profile_progressive_s1_offline.md"
cat > "$REQ2A" <<'EOF'
goal: progressive fallback s1 offline
online_lookup: false
online_failfast: true
min_complete_seeds: 3
EOF
TASK2A="$(run_case "s1_offline" "$REQ2A" "$W2/paper" "$W2/notes" "$W2/references/for_seeds" "0")"
python3 - <<PY
import json
from pathlib import Path
t = "$TASK2A"
p = json.loads(Path(f"AGENTS/tasks/{t}/outputs/paper_profile/paper_profile.json").read_text())
assert p["profile"]["seed_summary"]["found"] >= 1, p["profile"]["seed_summary"]
print("OK offline mode", t)
PY

mkdir -p AGENTS/cache/online_meta
mkdir -p AGENTS/cache/online_meta
cat > AGENTS/cache/online_meta/2502.10001.json <<'EOF'
{"title":"A title","abstract":"Abstract A","authors":["Alpha One"],"year":2024,"link":"https://arxiv.org/abs/2502.10001"}
EOF
cat > AGENTS/cache/online_meta/2502.10002.json <<'EOF'
{"title":"B title","abstract":"Abstract B","authors":["Beta Two"],"year":2024,"link":"https://arxiv.org/abs/2502.10002"}
EOF
cat > AGENTS/cache/online_meta/2502.10003.json <<'EOF'
{"title":"C title","abstract":"Abstract C","authors":["Gamma Three"],"year":2024,"link":"https://arxiv.org/abs/2502.10003"}
EOF
REQ2B="AGENTS/requests/regression/paper_profile_progressive_s1_online.md"
cat > "$REQ2B" <<'EOF'
goal: progressive fallback s1 online
online_lookup: true
online_failfast: true
min_complete_seeds: 3
EOF
TASK2B="test_paper_profile_progressive_s1_online_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK2B" --request "$REQ2B" >/tmp/paper_profile_progressive_start_s1_online.out
PAPER_PROFILE_USER_PAPER="$W2/paper" \
PAPER_PROFILE_USER_NOTES="$W2/notes" \
PAPER_PROFILE_USER_REFS_FOR_SEEDS="$W2/references/for_seeds" \
./bin/agenthub run --task "$TASK2B" --yes --online --net >/tmp/paper_profile_progressive_run_s1_online.out 2>/tmp/paper_profile_progressive_run_s1_online.err
python3 - <<PY
import json
from pathlib import Path
t = "$TASK2B"
p = json.loads(Path(f"AGENTS/tasks/{t}/outputs/paper_profile/paper_profile.json").read_text())
complete = [s for s in p["profile"]["seed_papers"] if s.get("completeness") == "COMPLETE"]
assert len(complete) >= 3, len(complete)
print("OK S1/S4 pass", t)
PY

echo "[3/3] no for_seeds, no bib, no tex -> hard fail (missing manuscript sources)"
W3="$(mktemp -d /tmp/paper_progressive_empty_XXXX)"
mkdir -p "$W3/paper" "$W3/notes" "$W3/references/for_seeds"
REQ3="AGENTS/requests/regression/paper_profile_progressive_empty.md"
cat > "$REQ3" <<'EOF'
goal: progressive fallback empty
online_lookup: false
min_complete_seeds: 3
EOF
TASK3="$(run_case "empty" "$REQ3" "$W3/paper" "$W3/notes" "$W3/references/for_seeds" "nonzero")"
ERR3="AGENTS/tasks/$TASK3/review/error.md"
[[ -f "$ERR3" ]] || { echo "FAIL: expected error.md"; exit 1; }
rg -q 'MISSING_MANUSCRIPT_SOURCES' "$ERR3" || { echo "FAIL: expected missing-source error"; exit 1; }

echo "PASS: progressive fallback regression checks passed"
