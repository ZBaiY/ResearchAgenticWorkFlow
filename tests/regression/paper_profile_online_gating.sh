#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

REQ_DIR="AGENTS/requests/regression"
mkdir -p "$REQ_DIR"

mk_rich_paper() {
  local paper="$1"
  local notes="$2"
  mkdir -p "$paper" "$notes"
  cat > "$paper/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Neutrino flavor conversion with ultralight dark matter couplings}
\begin{abstract}
We study neutrino oscillation phenomenology, matter effects, and dark-sector coupling constraints.
\end{abstract}
\section{Introduction}
We analyze Hamiltonian structure, baseline dependence, parameter inference, and robustness checks.
\bibliography{refs}
\cite{A2024,B2024,C2024}
\end{document}
EOF
  cat > "$notes/context.md" <<'EOF'
Keywords: neutrino oscillation, flavor conversion, ultralight dark matter, phenomenology, coupling constraints, baseline analyses.
EOF
}

echo "[a] offline-only: missing abstracts warns but does not hard-fail"
W1="$(mktemp -d /tmp/paper_online_gate_a_XXXX)"
mkdir -p "$W1/references/for_seeds"
mk_rich_paper "$W1/paper" "$W1/notes"
cat > "$W1/paper/refs.bib" <<'EOF'
@article{A2024,title={A title},author={Alpha One},year={2024},eprint={2503.10001},archivePrefix={arXiv}}
@article{B2024,title={B title},author={Beta Two},year={2024},eprint={2503.10002},archivePrefix={arXiv}}
@article{C2024,title={C title},author={Gamma Three},year={2024},eprint={2503.10003},archivePrefix={arXiv}}
EOF
REQ_A="$REQ_DIR/paper_profile_online_gate_offline.md"
cat > "$REQ_A" <<'EOF'
goal: online gating offline mode
online_lookup: false
min_complete_seeds: 3
EOF
TASK_A="test_paper_online_gate_offline_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK_A" --request "$REQ_A" >/tmp/paper_online_gate_a_start.out
PAPER_PROFILE_USER_PAPER="$W1/paper" PAPER_PROFILE_USER_NOTES="$W1/notes" PAPER_PROFILE_USER_REFS_FOR_SEEDS="$W1/references/for_seeds" \
./bin/agenthub run --task "$TASK_A" --yes >/tmp/paper_online_gate_a_run.out 2>/tmp/paper_online_gate_a_err.out
python3 - <<PY
import json
from pathlib import Path
t = "$TASK_A"
p = json.loads(Path(f"AGENTS/tasks/{t}/outputs/paper_profile/paper_profile.json").read_text())
assert p["profile"]["seed_summary"]["found"] >= 1, p["profile"]["seed_summary"]
r = json.loads(Path(f"AGENTS/tasks/{t}/logs/paper_profile_update/resolved_request.json").read_text())
assert r.get("online_requested") in (False, None), r
assert r.get("online_attempted") in (False, None), r
print("OK offline mode")
PY

echo "[b] online+net: attempts completion (non-blocking)"
W2="$(mktemp -d /tmp/paper_online_gate_b_XXXX)"
mkdir -p "$W2/references/for_seeds"
mk_rich_paper "$W2/paper" "$W2/notes"
cat > "$W2/paper/refs.bib" <<'EOF'
@article{A2024,title={A title},author={Alpha One},year={2024},eprint={2504.10001},archivePrefix={arXiv}}
@article{B2024,title={B title},author={Beta Two},year={2024},eprint={2504.10002},archivePrefix={arXiv}}
@article{C2024,title={C title},author={Gamma Three},year={2024},eprint={2504.10003},archivePrefix={arXiv}}
EOF
REQ_B="$REQ_DIR/paper_profile_online_gate_online.md"
cat > "$REQ_B" <<'EOF'
goal: online gating online mode
online_lookup: true
online_failfast: true
min_complete_seeds: 3
EOF
TASK_B="test_paper_online_gate_online_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK_B" --request "$REQ_B" >/tmp/paper_online_gate_b_start.out
mkdir -p AGENTS/cache/online_meta
cat > AGENTS/cache/online_meta/2504.10001.json <<'EOF'
{"title":"A title","abstract":"Abstract A","authors":["Alpha One"],"year":2024,"link":"https://arxiv.org/abs/2504.10001"}
EOF
cat > AGENTS/cache/online_meta/2504.10002.json <<'EOF'
{"title":"B title","abstract":"Abstract B","authors":["Beta Two"],"year":2024,"link":"https://arxiv.org/abs/2504.10002"}
EOF
cat > AGENTS/cache/online_meta/2504.10003.json <<'EOF'
{"title":"C title","abstract":"Abstract C","authors":["Gamma Three"],"year":2024,"link":"https://arxiv.org/abs/2504.10003"}
EOF
PAPER_PROFILE_USER_PAPER="$W2/paper" PAPER_PROFILE_USER_NOTES="$W2/notes" PAPER_PROFILE_USER_REFS_FOR_SEEDS="$W2/references/for_seeds" \
./bin/agenthub run --task "$TASK_B" --yes --online --net >/tmp/paper_online_gate_b_run.out 2>/tmp/paper_online_gate_b_err.out
python3 - <<PY
import json
from pathlib import Path
t = "$TASK_B"
r = json.loads(Path(f"AGENTS/tasks/{t}/logs/paper_profile_update/resolved_request.json").read_text())
assert r.get("online_requested") is True, r
assert r.get("net_allowed") is True, r
print("OK online+net completion path")
PY

echo "[c] online requested but net disabled -> warning, no failure"
W3="$(mktemp -d /tmp/paper_online_gate_c_XXXX)"
mkdir -p "$W3/references/for_seeds"
mk_rich_paper "$W3/paper" "$W3/notes"
cat > "$W3/paper/refs.bib" <<'EOF'
@article{A2024,title={A title},author={Alpha One},year={2024},eprint={2505.10001},archivePrefix={arXiv}}
@article{B2024,title={B title},author={Beta Two},year={2024},eprint={2505.10002},archivePrefix={arXiv}}
@article{C2024,title={C title},author={Gamma Three},year={2024},eprint={2505.10003},archivePrefix={arXiv}}
EOF
REQ_C="$REQ_DIR/paper_profile_online_gate_net_disabled.md"
cat > "$REQ_C" <<'EOF'
goal: online requested but net disabled
online_lookup: true
online_failfast: false
min_complete_seeds: 3
EOF
TASK_C="test_paper_online_gate_net_disabled_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK_C" --request "$REQ_C" >/tmp/paper_online_gate_c_start.out
PAPER_PROFILE_USER_PAPER="$W3/paper" PAPER_PROFILE_USER_NOTES="$W3/notes" PAPER_PROFILE_USER_REFS_FOR_SEEDS="$W3/references/for_seeds" \
./bin/agenthub run --task "$TASK_C" --yes --online >/tmp/paper_online_gate_c_run.out 2>/tmp/paper_online_gate_c_err.out
python3 - <<PY
import json
from pathlib import Path
t = "$TASK_C"
r = json.loads(Path(f"AGENTS/tasks/{t}/logs/paper_profile_update/resolved_request.json").read_text())
p = json.loads(Path(f"AGENTS/tasks/{t}/outputs/paper_profile/paper_profile.json").read_text())
assert r.get("online_requested") is True, r
assert r.get("net_allowed") is False, r
assert any("NETWORK_UNAVAILABLE" in x for x in p["profile"].get("warnings", [])), p["profile"].get("warnings", [])
print("OK net-missing warning path")
PY

echo "PASS: online completion and net gating regression checks passed"
