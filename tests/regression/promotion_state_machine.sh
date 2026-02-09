#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

REQ="AGENTS/requests/regression/promotion_state_machine.md"
mkdir -p "$(dirname "$REQ")"
cat > "$REQ" <<'EOF'
# Request
goal:
promotion pause model regression
EOF

PAPER_DIR="$(mktemp -d "/tmp/promo_sm_paper_XXXX")"
REFS_DIR="$(mktemp -d "/tmp/promo_sm_refs_XXXX")"
cat > "$PAPER_DIR/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
\title{Promotion State Machine Test}
\begin{abstract}Neutrino profile test for promotion state machine.</end{abstract}
\bibliography{references}
\cite{A2024}
\end{document}
EOF
cat > "$PAPER_DIR/references.bib" <<'EOF'
@article{A2024,title={Seed A},author={Alice One},year={2024}}
EOF
for i in 1 2 3; do
  cat > "$REFS_DIR/ref$i.txt" <<EOF
Title: Ref $i
Authors: Author $i
Abstract: text $i
arXiv:2401.0000$i
EOF
done
export PAPER_DIR REFS_DIR

USER_META="USER/paper/meta/paper_profile.json"
mkdir -p "$(dirname "$USER_META")"
BACKUP="$(mktemp "/tmp/promo_sm_user_meta_backup_XXXX")"
if [[ -f "$USER_META" ]]; then
  cp "$USER_META" "$BACKUP"
  HAD_USER_META=1
else
  HAD_USER_META=0
fi
cleanup() {
  if [[ "$HAD_USER_META" -eq 1 ]]; then
    cp "$BACKUP" "$USER_META"
  else
    rm -f "$USER_META"
  fi
  rm -f "$BACKUP"
}
trap cleanup EXIT

hash_user_meta() {
  if [[ -f "$USER_META" ]]; then
    shasum -a 256 "$USER_META" | awk '{print $1}'
  else
    echo "missing"
  fi
}

run_task_noninteractive() {
  local task="$1"
  python3 - <<PY
import os, subprocess
env = dict(os.environ)
env["PAPER_PROFILE_USER_PAPER"] = os.environ["PAPER_DIR"]
env["PAPER_PROFILE_USER_REFS_FOR_SEEDS"] = os.environ["REFS_DIR"]
cp = subprocess.run(
    ["./bin/agenthub", "run", "--task", "$task", "--yes"],
    stdin=subprocess.DEVNULL,
    text=True,
    capture_output=True,
    env=env,
)
print(f"RC={cp.returncode}")
print(cp.stdout)
print(cp.stderr)
PY
}

run_promote_interactive() {
  local task="$1"
  local answer="$2"
  python3 - "$task" "$answer" <<'PY'
import os, pty, select, sys

task_id = sys.argv[1]
answer = sys.argv[2]
cmd = ["./bin/agenthub", "promote", "--task", task_id]

pid, fd = pty.fork()
if pid == 0:
    os.execvpe(cmd[0], cmd, dict(os.environ))

buf = bytearray()
sent = False
while True:
    r, _, _ = select.select([fd], [], [], 0.2)
    if fd in r:
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        buf.extend(data)
        if (not sent) and b"PROMOTE_TO_USER? [y/N]" in buf:
            os.write(fd, (answer + "\n").encode("utf-8"))
            sent = True
_, status = os.waitpid(pid, 0)
rc = os.waitstatus_to_exitcode(status)
print(f"RC={rc}")
print(buf.decode("utf-8", errors="replace"))
PY
}

echo "[case a] interactive promote answer no => USER unchanged"
TASK_A="test_promo_sm_a_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK_A" --request "$REQ" >/tmp/promo_sm_a_start.out
RUN_A="$(run_task_noninteractive "$TASK_A")"
printf '%s\n' "$RUN_A"
grep -q 'PROMOTION_STATUS=READY' <<<"$RUN_A" || { echo "FAIL: case a missing PROMOTION_STATUS"; exit 1; }
H_A_BEFORE="$(hash_user_meta)"
PROM_A="$(run_promote_interactive "$TASK_A" "no")"
printf '%s\n' "$PROM_A"
H_A_AFTER="$(hash_user_meta)"
grep -q 'RC=0' <<<"$PROM_A" || { echo "FAIL: case a promote failed"; exit 1; }
grep -q 'PROMOTE_TO_USER=skipped reason=user_declined' <<<"$PROM_A" || { echo "FAIL: case a expected user_declined"; exit 1; }
[[ "$H_A_BEFORE" == "$H_A_AFTER" ]] || { echo "FAIL: case a USER changed"; exit 1; }

echo "[case b] interactive promote answer yes => USER updated"
TASK_B="test_promo_sm_b_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK_B" --request "$REQ" >/tmp/promo_sm_b_start.out
run_task_noninteractive "$TASK_B" >/tmp/promo_sm_b_run.out
H_B_BEFORE="$(hash_user_meta)"
PROM_B="$(run_promote_interactive "$TASK_B" "yes")"
printf '%s\n' "$PROM_B"
H_B_AFTER="$(hash_user_meta)"
grep -q 'RC=0' <<<"$PROM_B" || { echo "FAIL: case b promote failed"; exit 1; }
grep -q 'PROMOTE_TO_USER=done target=USER/paper/meta/paper_profile.json' <<<"$PROM_B" || { echo "FAIL: case b expected done target"; exit 1; }
[[ "$H_B_BEFORE" != "$H_B_AFTER" ]] || { echo "FAIL: case b USER did not change"; exit 1; }

echo "[case c] non-interactive run, agent_mode off => USER unchanged + PROMOTE.md exists"
TASK_C="test_promo_sm_c_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK_C" --request "$REQ" >/tmp/promo_sm_c_start.out
H_C_BEFORE="$(hash_user_meta)"
RUN_C="$(run_task_noninteractive "$TASK_C")"
printf '%s\n' "$RUN_C"
H_C_AFTER="$(hash_user_meta)"
grep -q 'RC=0' <<<"$RUN_C" || { echo "FAIL: case c run failed"; exit 1; }
grep -q "PROMOTE_PLAN_PATH: GATE/staged/$TASK_C/PROMOTE.md" <<<"$RUN_C" || { echo "FAIL: case c missing preview path"; exit 1; }
[[ -f "GATE/staged/$TASK_C/PROMOTE.md" ]] || { echo "FAIL: case c missing PROMOTE.md"; exit 1; }
[[ "$H_C_BEFORE" == "$H_C_AFTER" ]] || { echo "FAIL: case c USER changed"; exit 1; }

echo "[case d] non-interactive promote missing allow flag => USER unchanged, blocked with NEXT"
TASK_D="test_promo_sm_d_$(date -u +%Y%m%dT%H%M%SZ)"
./bin/agenthub start --skill paper_profile_update --task-name "$TASK_D" --request "$REQ" >/tmp/promo_sm_d_start.out
run_task_noninteractive "$TASK_D" >/tmp/promo_sm_d_run.out
H_D_BEFORE="$(hash_user_meta)"
PROM_D="$(./bin/agenthub promote --task "$TASK_D" --yes </dev/null)"
printf '%s\n' "$PROM_D"
H_D_AFTER="$(hash_user_meta)"
grep -q 'PROMOTE_TO_USER=skipped reason=noninteractive_requires_explicit_flags NEXT=./bin/agenthub promote --task '"$TASK_D"' --yes --allow-user-write-noninteractive' <<<"$PROM_D" || { echo "FAIL: case d expected skipped NEXT"; exit 1; }
[[ "$H_D_BEFORE" == "$H_D_AFTER" ]] || { echo "FAIL: case d USER changed"; exit 1; }

echo "PASS: promotion state machine regression checks passed"
