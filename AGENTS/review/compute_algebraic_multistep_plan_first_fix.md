# compute_algebraic_multistep plan-first fix

## Root cause findings
- Latency/noise in the provided interaction did not originate from repo runtime scripts; no `Explored`, `functions.exec_command`, or non-English prompt strings are emitted by `bin/agenthub` schema paths.
- `bin/agenthub` `cmd_run` always executed post-run staging/promotion summary after any successful skill subprocess; for plan-only multistep runs this mixed plan review state with promotion messaging.
- `cmd_run` also relayed skill stderr to user output unconditionally, allowing noisy text leakage.

## Files changed
- `bin/agenthub`
- `tests/regression/compute_algebraic_multistep.sh`

## STOP/plan-first behavior now
- Multistep default run (`agenthub run --task <id>`) now exits before staging/promotion summary with:
  - `PLAN_STATUS=READY_FOR_REVIEW`
  - `EXECUTION_ALLOWED=false`
  - `STOP_REASON=need_user_review`
  - `PLAN_PATH=...`
  - `REPORT_PLAN_PATH=...`
- Plan phase no longer emits promotion markers/talk.
- Skill stderr is only forwarded when `AGENTHUB_DEBUG=1`; normal mode suppresses stderr noise.
- Added `agenthub plan-revise --task <id> --feedback "..."` to regenerate plan-only output without execution.
- When `compute_algebraic_multistep` request collection reaches `REQUEST_COMPLETE=true`, `agenthub request-set` now auto-generates the plan (plan-only) and returns review-stop markers without execution.

## Output hygiene behavior
- `bin/agenthub` now sanitizes skill stdout in normal mode and strips trace/noise lines containing tool-runner markers (for example `functions.exec_command`, `recipient_name`, `tool_uses`).
- Dropped noisy lines are written to `AGENTS/tasks/<TASK_ID>/review/trace_debug.log`.
- Non-business and non-ASCII contamination lines are removed from normal user-visible output.

## Tests added/updated
- `tests/regression/compute_algebraic_multistep.sh` now asserts:
  - schema-step outputs are clean (no tool-trace markers, no non-business Chinese noise, no non-ASCII bytes)
  - schema-completion auto-plan emits `PLAN_STATUS=READY_FOR_REVIEW` and `STOP_REASON=need_user_review`
  - default multistep run remains plan-only with `STOP_REASON=need_user_review`
  - plan phase output has no promotion markers/wording
  - execution artifacts are absent before explicit `--execute`
