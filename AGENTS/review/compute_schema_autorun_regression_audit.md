# Compute Schema Autorun Regression Audit

## 1) Timeline of the observed behavior
1. User routes compute intent and picks candidate `2` (`compute_algebraic`).
2. System reaches schema collection state (`REQUEST_STEP=goal`, `REQUEST_COMPLETE=false`) and prompts for goal.
3. User provides one answer (goal).
4. Assistant/orchestrator then chains extra commands in the same turn:
   - additional `agenthub request-set` for `inputs`, `expected_outputs`, `constraints`, `preferred_formats`
   - then `agenthub run --task ... --skill compute_algebraic --yes`
5. One chained call fails strict ordering (`Expected field 'inputs' next, got 'expected_outputs'`).
6. After forced completion, run executes and fails in skill runtime because Wolfram backend is missing.

This violates the intended contract: one field persisted per user turn, then stop and ask the next question.

## 2) Root-cause analysis (CLI vs orchestration layer)
Conclusion: this regression is orchestration-layer behavior, not core CLI auto-execution.

Evidence:
- Repo text search does not contain orchestration phrases from the bad behavior (e.g., "fill the remaining required request fields", "minimal defaults so the run can proceed", "run it through the router flow").
- `agenthub request-set` updates exactly one field per invocation and exits (`bin/agenthub:700-824`), with strict next-field enforcement (`bin/agenthub:734-735`).
- `agenthub` only runs subcommands explicitly selected by argv dispatch (`bin/agenthub:1498-1513`); no implicit background chaining exists.
- `bart` (`bin/a`) does not issue `request-set`; for compute it stops when request is incomplete (`bin/a:714-721`).
- Helper scripts that chain all request steps are regression tests, not runtime hooks (`tests/regression/compute_request_completion.sh:48-111`).

Why CLI cannot fully prevent this today:
- CLI emits step markers/prompt text but no explicit terminal STOP semantic after each schema write (`bin/agenthub:817-824`).
- An external orchestrator can still decide to issue additional `request-set` commands immediately, because CLI currently has no per-turn lock/token or hard "must return to user" gate.

## 3) Specific divergence from intended UX contract
Intended:
- one question per step
- one persisted field per user answer
- stop and ask next question
- no auto-fill
- no auto-run unless explicitly requested

Actual divergence in observed run:
- multiple `request-set` calls executed after a single answer (assistant-side chaining)
- attempted out-of-order field update (caught by CLI)
- automatic `run` call without explicit user request for execution in that turn

Contract enforcement present in repo but bypassed by orchestration decisions:
- strict field order is enforced (`bin/agenthub:734-735`)
- incomplete request should pause run (`bin/agenthub:1243-1255`, `bin/a:714-721`)
- no continuation tokens are already tested (`tests/regression/compute_request_completion.sh:7-10`, `tests/regression/compute_no_continuation_tokens.sh:20-37`)

## 4) Minimal fix recommendations (no implementation)
- Add explicit STOP markers after each schema write.
  - File: `bin/agenthub:817-824`
  - Change: after printing `REQUEST_STEP`/`REQUEST_COMPLETE`, always print:
    - `STOP_REASON=need_user_input` when `REQUEST_COMPLETE=false`
    - `STOP_REASON=request_complete_waiting_user_run` when `REQUEST_COMPLETE=true`
  - Behavior goal: downstream orchestrators get a machine-readable hard stop signal after one `request-set` call.

- Add explicit STOP markers in compute start/run pause paths too.
  - File: `bin/agenthub:886-891` (start for compute)
  - File: `bin/agenthub:1248-1255` (run paused for missing request fields)
  - Change: append `STOP_REASON=need_user_input` in both paths.
  - Behavior goal: consistent stop contract at every schema-input boundary.

- Keep `bart --run` compute gate as non-executing on incomplete schema and make it explicit.
  - File: `bin/a:714-721`
  - Change: add `STOP_REASON=need_user_input` to this early-return path.
  - Behavior goal: wrapper output cannot be misread as "continue running".

- Prevent accidental multi-field answer handling in one orchestration pass (defensive local gate).
  - File: `bin/agenthub:700-824`
  - Change: optional minimal guard via `--turn-token <id>` or `--expect-step <name>` arg; reject if token/step mismatches current state.
  - Behavior goal: even if an orchestrator tries chaining, only the first intentional step for that user turn succeeds.

- No helper auto-fill to remove in runtime code; keep tests isolated.
  - File evidence: `tests/regression/compute_request_completion.sh:48-111` is explicit test scripting, not production flow.
  - Change: none in runtime behavior; document test-only nature and avoid copying that sequence into orchestration prompts.

- Preserve strict separation between request completion and execution.
  - File: `bin/agenthub:1243-1255` and `bin/a:723-734`
  - Change: no auto-run trigger when request transitions to complete; require explicit user-issued run command.
  - Behavior goal: `REQUEST_COMPLETE=true` is state only, never execution intent.

## 5) Test plan
Add/extend regression tests to enforce the contract at CLI boundary:

- One question per step, one field per command
  - Extend `tests/regression/compute_request_completion.sh`
  - Assert each `request-set` call mutates only the targeted field and leaves later fields untouched until separately set.

- No automatic request-set chaining
  - New test: `tests/regression/compute_no_autochain_markers.sh`
  - For each `request-set` response, assert:
    - contains `REQUEST_STEP=<next>`
    - contains `REQUEST_COMPLETE=false` (until done)
    - contains `STOP_REASON=need_user_input`
    - does not contain shell-like continuation tokens (`./`, `bash`, `RUN_COMMAND=`, `NEXT*`).

- No automatic run after request completion
  - New test: after setting `preferred_formats` (done), assert no `work/report.md` exists until explicit `agenthub run` is invoked.
  - Reuse checks patterned after `tests/regression/compute_run_gate.sh:50-61`.

- No runnable hint surfaces
  - Extend forbidden-token matcher used in `tests/regression/compute_request_completion.sh:7-10` and `tests/regression/compute_no_continuation_tokens.sh`.
  - Add assertions for absence of implied execution hints in schema responses (e.g., lines containing `--run`, `run now`, `execute`).
