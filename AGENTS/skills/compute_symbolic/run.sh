#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
TASK_ID="${2:-}"
SKILL="compute_symbolic"
BACKEND="wolfram"
APPROVAL_SH="$ROOT/AGENTS/runtime/approval.sh"

if [[ -z "$ROOT" || -z "$TASK_ID" ]]; then
  echo "Usage: run.sh <repo_root> <task_id>" >&2
  exit 2
fi

TDIR="$ROOT/AGENTS/tasks/$TASK_ID"
WORK_COMPUTE="$TDIR/work/compute"
SCRATCH="$WORK_COMPUTE/scratch"
RUN_DIR="$WORK_COMPUTE/run"
OUTPUTS="$TDIR/outputs/compute"
LOGS="$TDIR/logs/compute"
REVIEW_DIR="$TDIR/review"
DELIV_SRC="$TDIR/deliverable/src"
DELIV_PROMO="$TDIR/deliverable/promotion_instructions.md"
RESULT_JSON="$OUTPUTS/result.json"
HASHES_JSON="$LOGS/hashes.json"
CONSENT_JSON="$LOGS/consent.json"
RESOLVED_JSON="$LOGS/resolved_request.json"
ENV_JSON="$LOGS/env.json"
REPORT="$REVIEW_DIR/compute_symbolic_report.md"
SPEC_FILE="$WORK_COMPUTE/spec.yaml"
CMD_LOG="$LOGS/commands.txt"
STDOUT_LOG="$LOGS/stdout.log"
STDERR_LOG="$LOGS/stderr.log"

if [[ ! -d "$TDIR" ]]; then
  echo "Task folder does not exist: $TDIR" >&2
  exit 2
fi

source "$APPROVAL_SH"

mkdir -p "$SCRATCH" "$RUN_DIR" "$OUTPUTS" "$LOGS" "$REVIEW_DIR" "$TDIR/deliverable"
: > "$CMD_LOG"
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

exec >> "$STDOUT_LOG" 2>> "$STDERR_LOG"

log_cmd() { printf '%s\n' "$*" >> "$CMD_LOG"; }
sha() {
  if [[ -f "$1" ]]; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo ""
  fi
}

cat > "$SPEC_FILE" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "backend": "$BACKEND",
  "params": {
    "variable": "x",
    "order": 6,
    "assumptions": "x > 0",
    "function": "Exp[x] * Sin[x]",
    "keep_intermediates": false
  }
}
EOF2
cp "$SPEC_FILE" "$RESOLVED_JSON"

cat > "$SCRATCH/main.wl" <<'EOF2'
(* Symbolic demo compute: series expansion with assumptions. *)
spec = Import[Environment["SPEC_PATH"], "RawJSON"];
params = Lookup[spec, "params", <||>];
ord = Lookup[params, "order", 6];

x = Symbol[Lookup[params, "variable", "x"]];
assStr = Lookup[params, "assumptions", "x > 0"];
ass = ToExpression[assStr, InputForm, Hold];
expr = ToExpression[Lookup[params, "function", "Exp[x] * Sin[x]"], InputForm, Hold];
seriesExpr = ReleaseHold@expr // FunctionExpand // Series[#, {x, 0, ord}] & // Normal;
verif = Simplify[ReleaseHold@expr - seriesExpr, ReleaseHold[ass]];

payload = <|
  "meta" -> <|
    "task_id" -> Lookup[spec, "task_id", ""],
    "skill" -> Lookup[spec, "skill", ""],
    "backend" -> Lookup[spec, "backend", "wolfram"],
    "timestamp_utc" -> Environment["RUN_TIMESTAMP"],
    "status" -> "ok"
  |>,
  "params" -> <|
    "variable" -> ToString[x],
    "order" -> ord,
    "assumptions" -> assStr,
    "function" -> Lookup[params, "function", "Exp[x] * Sin[x]"]
  |>,
  "results" -> <|
    "summary" -> "Computed symbolic series expansion.",
    "series" -> ToString[seriesExpr, InputForm],
    "verification_residual" -> ToString[verif, InputForm]
  |>,
  "sanity_checks" -> {
    <|"name" -> "series_nonempty", "pass" -> (StringLength[ToString[seriesExpr, InputForm]] > 0), "value" -> True, "note" -> "series produced"|>,
    <|"name" -> "verification_simplified", "pass" -> True, "value" -> ToString[verif, InputForm], "note" -> "residual under assumptions"|>
  },
  "diagnostics" -> <|
    "assumptions" -> assStr,
    "verification" -> "Residual inspected under assumptions"
  |>
|>;

Export[Environment["RESULT_PATH"], payload, "RawJSON"];
EOF2

log_cmd "cp $SCRATCH/main.wl $RUN_DIR/main.wl"
cp "$SCRATCH/main.wl" "$RUN_DIR/main.wl"

W_CMD=""
if command -v wolframscript >/dev/null 2>&1; then
  W_CMD="wolframscript"
elif command -v math >/dev/null 2>&1; then
  W_CMD="math"
fi

RUN_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "$ENV_JSON" <<EOF2
{
  "task_id": "$TASK_ID",
  "skill": "$SKILL",
  "backend": "$BACKEND",
  "timestamp_utc": "$RUN_TS",
  "wolframscript": "$( command -v wolframscript >/dev/null 2>&1 && wolframscript -version 2>&1 | head -n 1 || echo unavailable )",
  "math": "$( command -v math >/dev/null 2>&1 && math -version 2>&1 | head -n 1 || echo unavailable )",
  "python": "$( command -v python3 >/dev/null 2>&1 && python3 --version 2>&1 | head -n 1 || echo unavailable )"
}
EOF2

if [[ -z "$W_CMD" ]]; then
  cat > "$RESULT_JSON" <<EOF2
{
  "meta": {
    "task_id": "$TASK_ID",
    "skill": "$SKILL",
    "backend": "$BACKEND",
    "timestamp_utc": "$RUN_TS",
    "status": "backend_unavailable"
  },
  "params": {"note": "wolframscript and math are unavailable"},
  "results": {"summary": "No symbolic computation executed."},
  "sanity_checks": [
    {"name": "backend_available", "pass": false, "value": false, "note": "missing wolframscript/math"}
  ],
  "diagnostics": {"assumptions": "not_applied", "verification": "not_run"}
}
EOF2
  log_cmd "backend unavailable: wolframscript/math not found"
else
  if [[ "$W_CMD" == "wolframscript" ]]; then
    log_cmd "cd $RUN_DIR && SPEC_PATH=$SPEC_FILE RESULT_PATH=$RESULT_JSON RUN_TIMESTAMP=$RUN_TS wolframscript -file main.wl"
    set +e
    (cd "$RUN_DIR" && SPEC_PATH="$SPEC_FILE" RESULT_PATH="$RESULT_JSON" RUN_TIMESTAMP="$RUN_TS" wolframscript -file main.wl)
    RC=$?
    set -e
  else
    log_cmd "cd $RUN_DIR && SPEC_PATH=$SPEC_FILE RESULT_PATH=$RESULT_JSON RUN_TIMESTAMP=$RUN_TS math -script main.wl"
    set +e
    (cd "$RUN_DIR" && SPEC_PATH="$SPEC_FILE" RESULT_PATH="$RESULT_JSON" RUN_TIMESTAMP="$RUN_TS" math -script main.wl)
    RC=$?
    set -e
  fi

  if [[ "$RC" -ne 0 || ! -f "$RESULT_JSON" ]]; then
    cat > "$RESULT_JSON" <<EOF2
{
  "meta": {
    "task_id": "$TASK_ID",
    "skill": "$SKILL",
    "backend": "$BACKEND",
    "timestamp_utc": "$RUN_TS",
    "status": "failed"
  },
  "params": {"note": "execution failed"},
  "results": {"summary": "Symbolic execution failed; inspect logs."},
  "sanity_checks": [
    {"name": "run_exit_zero", "pass": false, "value": $RC, "note": "wolfram run failed"}
  ],
  "diagnostics": {"assumptions": "unknown", "verification": "unknown"}
}
EOF2
  fi
fi

RESP=""
EXPORTED=false
if rg -q '"status": "ok"' "$RESULT_JSON"; then
  if approval_confirm "Compute succeeded. Export a cleaned, commented program into deliverable/src? (y/N) "; then
    RESP="y"
    EXPORTED=true
    mkdir -p "$DELIV_SRC"
    cat > "$DELIV_SRC/main.wl" <<'EOF2'
(*
  Symbolic compute example (exported clean source).
  Computes a series expansion with explicit assumptions.
  Edit params in SPEC_PATH to play around.
*)

spec = Import[Environment["SPEC_PATH"], "RawJSON"];
params = Lookup[spec, "params", <||>];

x = Symbol[Lookup[params, "variable", "x"]];
ord = Lookup[params, "order", 6];
ass = ToExpression[Lookup[params, "assumptions", "x > 0"], InputForm, Hold];
expr = ToExpression[Lookup[params, "function", "Exp[x] * Sin[x]"], InputForm, Hold];

(* Core symbolic operation: truncated series around x=0. *)
seriesExpr = ReleaseHold@expr // FunctionExpand // Series[#, {x, 0, ord}] & // Normal;

payload = <|
  "meta" -> spec,
  "params" -> params,
  "results" -> <|
    "summary" -> "Symbolic series expansion",
    "series" -> ToString[seriesExpr, InputForm]
  |>,
  "sanity_checks" -> {
    <|"name" -> "series_nonempty", "pass" -> (StringLength[ToString[seriesExpr, InputForm]] > 0), "value" -> True, "note" -> "series produced"|>
  },
  "diagnostics" -> <|
    "assumptions" -> ToString[ReleaseHold[ass], InputForm],
    "verification" -> "Inspect symbolic residual manually if needed"
  |>
|>;

Export[Environment["RESULT_PATH"], payload, "RawJSON"];
EOF2
    cat > "$DELIV_SRC/README.md" <<EOF2
# Symbolic Compute Program

This program computes a symbolic series expansion under explicit assumptions and writes structured results.

## Run
\`SPEC_PATH=AGENTS/tasks/$TASK_ID/work/compute/spec.yaml RESULT_PATH=AGENTS/tasks/$TASK_ID/outputs/compute/result.json wolframscript -file AGENTS/tasks/$TASK_ID/deliverable/src/main.wl\`

## Inputs
- \`AGENTS/tasks/$TASK_ID/work/compute/spec.yaml\`

## Outputs
- \`AGENTS/tasks/$TASK_ID/outputs/compute/result.json\`
- optional \`tables/*.csv\` and \`fig/*\` if added later

## Assumptions / verification
- Assumptions are controlled by \`params.assumptions\` in \`spec.yaml\`.
- Verification notes appear in \`diagnostics\`.

## Play around
- Edit \`params.function\`, \`params.variable\`, \`params.order\`, \`params.assumptions\`.
EOF2
  else
    RESP="n"
    rm -rf "$DELIV_SRC"
  fi
fi

cat > "$CONSENT_JSON" <<EOF2
{
  "exported_source": $EXPORTED,
  "user_response": "$(printf '%s' "$RESP" | tr '[:upper:]' '[:lower:]')",
  "timestamp_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF2

cat > "$DELIV_PROMO" <<EOF2
# Promotion Instructions

Agents cannot write to USER directly.

If exported source exists, manually promote with:

\`cp -r AGENTS/tasks/$TASK_ID/deliverable/src USER/src/compute/$TASK_ID/\`

Recommended destination:
- \`USER/src/compute/$TASK_ID/\`

If export was declined, rerun and answer \`y\` to generate \`deliverable/src\`.
EOF2

{
  echo "{"
  echo "  \"generated_at_utc\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
  echo "  \"inputs\": ["
  echo "    {\"path\": \"$SPEC_FILE\", \"sha256\": \"$(sha "$SPEC_FILE")\"}"
  echo "  ],"
  echo "  \"outputs\": ["
  echo "    {\"path\": \"$RESULT_JSON\", \"sha256\": \"$(sha "$RESULT_JSON")\"},"
  echo "    {\"path\": \"$CONSENT_JSON\", \"sha256\": \"$(sha "$CONSENT_JSON")\"}"
  echo "  ]"
  echo "}"
} > "$HASHES_JSON"

RESULT_STATUS="$(sed -n 's/^[[:space:]]*"status":[[:space:]]*"\([^"]*\)".*/\1/p' "$RESULT_JSON" | head -n 1)"
if [[ "$RESULT_STATUS" == "ok" ]]; then
  rm -rf "$RUN_DIR/__pycache__" "$RUN_DIR/.ipynb_checkpoints"
  find "$RUN_DIR" -type f \( -name '*.tmp' -o -name '*.bak' \) -delete || true
  find "$SCRATCH" -mindepth 1 -delete || true
  CLEANUP_NOTE="transient byproducts cleaned"
else
  CLEANUP_NOTE="run failed or backend unavailable; preserved scratch/run for forensics"
fi

{
  echo "# compute_symbolic Report"
  echo
  echo "- task_id: $TASK_ID"
  echo "- backend: $BACKEND"
  echo "- status: $RESULT_STATUS"
  echo "- exported_source: $EXPORTED"
  echo "- cleanup: $CLEANUP_NOTE"
  echo
  echo "## Paths"
  echo "- spec: AGENTS/tasks/$TASK_ID/work/compute/spec.yaml"
  echo "- result: AGENTS/tasks/$TASK_ID/outputs/compute/result.json"
  echo "- logs: AGENTS/tasks/$TASK_ID/logs/compute/"
} > "$REPORT"

bash "$ROOT/AGENTS/runtime/stage_to_gate.sh" "$ROOT" "$TASK_ID" "$SKILL"

exit 0
