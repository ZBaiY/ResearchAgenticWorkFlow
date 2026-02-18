# compute_algebraic_multistep phase3-skip audit

## 1) Call graph (plan/execute path)
- `bart --pick/--start`:
  - resolves skill/task and runs `agenthub start` for compute skills (`bin/a:703-710`).
  - does not pass `--execute`.
- `bart --run`:
  - invokes `agenthub run --task <id>` with only `--yes/--no` propagation (`bin/a:726-734`).
  - no `--execute` injection in wrapper path.
- `agenthub run`:
  - parses `--execute` as explicit CLI flag (`bin/agenthub:1642`).
  - maps execute mode strictly from CLI arg: `COMPUTE_EXECUTE = 1 if args.execute else 0` (`bin/agenthub:1340`).
  - dispatches skill via `agentctl run` (`bin/agenthub:1342-1344`).
- skill runner (`compute_algebraic_multistep`):
  - plan-only if `COMPUTE_EXECUTE!=1` (`AGENTS/skills/compute_algebraic_multistep/scripts/run.sh:255-260`).
  - execution branch only when `COMPUTE_EXECUTE==1` (`.../run.sh:255`, then execution logic from `:262` onward).

## 2) State machine as implemented
- Schema done marker from `request-set`:
  - prints `REQUEST_STEP=done`, `REQUEST_COMPLETE=true`, `STOP_REASON=request_complete_waiting_user_run` (`bin/agenthub:884-889`).
  - no run/plan auto-trigger in done branch.
- Default run (no `--execute`) for multistep:
  - prints `PLAN_STATUS=READY_FOR_REVIEW`, `EXECUTION_ALLOWED=false`, `STOP_REASON=need_user_review` and returns (`bin/agenthub:1371-1379`).
- Execute run:
  - only when caller includes `--execute` (`bin/agenthub:1340`, parser `:1642`).

## 3) Root cause of "phase3 skipped"
- Primary cause: caller/orchestrator invoked explicit execute command (`./bin/agenthub run --task ... --yes --execute`).
- Evidence:
  - execute mode in runtime is only flag-driven (`bin/agenthub:1340`, `:1642`).
  - `bart` wrapper path does not auto-append `--execute` (`bin/a:726-734`).
- Result: phase 3 is bypassed by command selection upstream, not by default run behavior.

## 4) Is this repo bug or external behavior?
- Primary classification: **external orchestrator behavior** (explicitly choosing `--execute`).
- Secondary repo-side gap: there is no hard precondition check requiring a prior review/ready latch before honoring `--execute`.
  - Current code accepts `--execute` whenever request is complete; no `READY_TO_EXECUTE` state gate check exists in `cmd_run`.

## 5) Minimal fix list (recommendations only, no implementation)
- Add execute precondition gate in `agenthub run` for multistep:
  - if `--execute` and no explicit review-ready marker in task state, block with `STOP_REASON=need_user_review`.
- Record review-ready latch after explicit user confirmation path (CLI-visible, non-runnable marker).
- Keep default run unchanged as plan-only and require explicit second-step execute after latch.
