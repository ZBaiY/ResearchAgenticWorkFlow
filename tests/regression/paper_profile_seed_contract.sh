#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

run_case() {
  local tag="$1"
  local missing_abs="$2"
  local online_lookup="$3"
  local force_net_fail="$4"

  local work="$(mktemp -d /tmp/paper_seed_contract_${tag}_XXXX)"
  local paper="$work/paper"
  local notes="$work/notes"
  local refs="$work/references/for_seeds"
  mkdir -p "$paper" "$notes" "$refs"

  cat > "$paper/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Seed Contract Paper}
\begin{abstract}Neutrino oscillation and dark matter phenomenology.\end{abstract}
\input{sec1}
\bibliography{refs}
\end{document}
EOF

  cat > "$paper/sec1.tex" <<'EOF'
We cite \cite{Good2024,Bad2023} and discuss flavor conversion in ultralight dark matter.
EOF

  if [[ "$missing_abs" == "yes" ]]; then
    cat > "$paper/refs.bib" <<'EOF'
@article{Good2024,title={Good Seed Paper},author={Alice Smith},year={2024},abstract={Detailed abstract for good seed.},eprint={2407.11111},archivePrefix={arXiv}}
@article{Bad2023,title={Bad Seed Missing Abstract},author={Bob Doe},year={2023},eprint={2301.22222},archivePrefix={arXiv}}
EOF
  else
    cat > "$paper/refs.bib" <<'EOF'
@article{Good2024,title={Good Seed Paper},author={Alice Smith},year={2024},abstract={Detailed abstract for good seed.},eprint={2407.11111},archivePrefix={arXiv}}
@article{Bad2023,title={Second Good Seed},author={Bob Doe},year={2023},abstract={Abstract for second seed},eprint={2301.22222},archivePrefix={arXiv}}
EOF
  fi

  cat > "$notes/idea.txt" <<'EOF'
Neutrino phenomenology and ultralight dark matter coupling constraints.
EOF

  # PDF surrogate (plain text named .pdf) to exercise pdf path.
  cat > "$refs/ref_pdf_surrogate.pdf" <<'EOF'
PDF SURROGATE TITLE
Authors: Carol Roe
Abstract: This surrogate PDF contains abstract text for valid seed extraction.
arXiv:2408.33333
EOF
  cat > "$refs/ref2.txt" <<'EOF'
Dark matter flavor conversion review
Authors: Dan Poe
Abstract: Review of flavor conversion and dark matter interactions.
arXiv:2408.44444
EOF
  cat > "$refs/ref3.txt" <<'EOF'
Long baseline neutrino constraints
Authors: Erin Moe
Abstract: Constraints from long baseline oscillation measurements.
arXiv:2408.55555
EOF

  local req="AGENTS/requests/regression/paper_seed_contract_${tag}.md"
  mkdir -p "$(dirname "$req")"
  cat > "$req" <<EOF
# Request
Goal:
seed contract test
online_lookup: $online_lookup
EOF

  local task="test_paper_seed_contract_${tag}_$(date -u +%Y%m%dT%H%M%SZ)"
  ./bin/agenthub start --skill paper_profile_update --task-name "$task" --request "$req" >/tmp/paper_seed_contract_start_${tag}.out

  set +e
  if [[ "$force_net_fail" == "yes" ]]; then
    PAPER_PROFILE_USER_PAPER="$paper" \
    PAPER_PROFILE_USER_NOTES="$notes" \
    PAPER_PROFILE_USER_REFS_FOR_SEEDS="$refs" \
    PAPER_PROFILE_ARXIV_API_BASE="http://127.0.0.1:9/api" \
    ./bin/agenthub run --task "$task" --yes --online >/tmp/paper_seed_contract_run_${tag}.out 2>/tmp/paper_seed_contract_run_${tag}.err
    rc=$?
  else
    PAPER_PROFILE_USER_PAPER="$paper" \
    PAPER_PROFILE_USER_NOTES="$notes" \
    PAPER_PROFILE_USER_REFS_FOR_SEEDS="$refs" \
    ./bin/agenthub run --task "$task" --yes >/tmp/paper_seed_contract_run_${tag}.out 2>/tmp/paper_seed_contract_run_${tag}.err
    rc=$?
  fi
  set -e

  echo "$task" > "/tmp/paper_seed_contract_task_${tag}.txt"
  return $rc
}

echo "[1/4] missing-abstract bib entry is invalid"
run_case "missing_abs" "yes" "false" "no"
TASK1="$(cat /tmp/paper_seed_contract_task_missing_abs.txt)"
export TASK1
python3 - <<'PY'
import json
import os
from pathlib import Path

task = os.environ["TASK1"]
p = json.loads(Path(f"AGENTS/tasks/{task}/outputs/paper_profile/paper_profile.json").read_text())
assert len(p["profile"]["seed_papers"]) >= 3
bad = [x for x in p["profile"]["seed_papers"] if x.get("title") == "Bad Seed Missing Abstract"]
assert not bad, "missing-abstract seed should be invalid"
print("OK missing-abstract invalid")
PY

echo "[2/4] pdf with abstract contributes valid seed"
python3 - <<'PY'
import json
import os
from pathlib import Path

task = os.environ["TASK1"]
p = json.loads(Path(f"AGENTS/tasks/{task}/outputs/paper_profile/paper_profile.json").read_text())
assert any("pdf" in str(x.get("source_path", "")).lower() for x in p["profile"]["seed_papers"]), "expected pdf-derived seed"
print("OK pdf-derived seed present")
PY

echo "[3/4] online_lookup=false performs local-only flow"
python3 - <<'PY'
import json
import os
from pathlib import Path

task = os.environ["TASK1"]
r = json.loads(Path(f"AGENTS/tasks/{task}/logs/paper_profile_update/resolved_request.json").read_text())
assert r.get("online_lookup") in (False, None), r
print("OK online disabled")
PY

echo "[4/4] online_lookup=true with network failure failfast"
if run_case "net_fail" "yes" "true" "yes"; then
  echo "FAIL: expected network failfast" >&2
  exit 1
fi
TASK2="$(cat /tmp/paper_seed_contract_task_net_fail.txt)"
ERR2="$(cat AGENTS/tasks/$TASK2/logs/paper_profile_update/stderr.log || true)"
printf '%s\n' "$ERR2"
if ! printf '%s\n' "$ERR2" | rg -q 'NETWORK_LOOKUP_FAILED'; then
  echo "FAIL: missing NETWORK_LOOKUP_FAILED" >&2
  exit 1
fi

echo "PASS: paper_profile seed contract regression checks passed"
