# compute_algebraic_multistep schema loop regression audit

## Executive summary
Primary responsible layer: **C) external orchestrator layer / wrapper prompt logic (outside repo)**.

Confidence: **high (~0.97)**.

Why:
- The observed prose/tool-trace strings are not emitted by repo runtime entrypoints (`bart`, `agenthub`, skill run script).
- `bart --pick 1` does not call `request-set`; it only resolves skill, creates task/request, and invokes `agenthub start` for compute skills.
- `agenthub request-set` enforces one-field-at-a-time sequencing (`field` must equal `current_step`) and returns stop markers after each field.
- Task artifacts for `compute_algebraic_multistep_20260217T055815Z` do not contain the exploration/prose strings.

## Step 1: string provenance scan (static)
Requested phrases scanned literally across repo.

### Hits
- `Explored`
  - `tests/regression/compute_algebraic_multistep.sh:14` (forbidden-token assertion only)
  - `AGENTS/review/compute_algebraic_multistep_plan_first_fix.md:4` (historical audit note)
  - `AGENTS/review/compute_multistep_output_contamination_audit.json:14`
  - `AGENTS/review/compute_multistep_output_contamination_audit.json:19`

### No hits (exact literal)
- `I’ll locate how this project expects`
- `Search compute_algebraic_multistep|PICK_REQUIRED|RECOMMENDED_SKILL|bart in .`
- `I’m checking the generated request files`
- `prefill`
- `Since you gave only a broad request, I’m proceeding with a concrete default`
- `minimize back-and-forth`
- `I’ve filled the remaining request fields`
- `Ran sed -n`
- `Ran ls -la`
- `Ran cat`
- `Ran ./bin/agenthub --help`

Interpretation: bad-output strings are not sourced from repo runtime code; only tests/audits reference a subset as forbidden/debug tokens.

## Step 2: call graph reconstruction (dynamic/structural)

### `bart "..." --pick 1` behavior
- Candidate rendering markers are printed by `print_suggestions`:
  - `bin/a:443-470` (`PICK_REQUIRED`, `RECOMMENDED_SKILL`).
- On `--pick` path:
  - resolve selected skill: `bin/a:651-660`
  - generate task name via `agenthub task-name`: `bin/a:666-671`
  - write request template: `bin/a:673`
  - build `agenthub start` command: `bin/a:679-688`
  - for compute skills with no `--start/--run`, it **still runs start** and prints start output: `bin/a:690-695`
- No `request-set` invocation from `bart` pick path.

### `agenthub request-set` behavior
- Entry: `cmd_request_set`: `bin/agenthub:767`.
- Enforces valid skill/field and strict next-step ordering:
  - allowed field check `bin/agenthub:779-782`
  - expected step guard `bin/agenthub:800-802`
- Processes exactly one `--field` + one value/file per call (`bin/agenthub:803-817`) and updates one field (`bin/agenthub:818-865`).
- Emits stop markers each call:
  - `REQUEST_FIELD_UPDATED`, `REQUEST_STEP`, `REQUEST_COMPLETE`: `bin/agenthub:884-886`
  - if not done: `STOP_REASON=need_user_input` + question: `bin/agenthub:937-939`
- Therefore chaining multiple `request-set` calls requires an external caller loop; not auto-chained inside one `request-set` execution.

### `compute_algebraic_multistep/scripts/run.sh` behavior
- Validates `request.json`; if incomplete, pauses for input markers (`AGENTS/skills/compute_algebraic_multistep/scripts/run.sh:30-53`, `:102-120`).
- Generates plan/report from existing request fields; does not collect fields interactively (`:122-260`).
- Executes WL only with `COMPUTE_EXECUTE=1` (`:255-340+`).
- No repo exploration commands or orchestration prose are emitted.

## Step 3: task artifact inspection (dynamic evidence)
Task: `compute_algebraic_multistep_20260217T055815Z`

Checked:
- `AGENTS/tasks/compute_algebraic_multistep_20260217T055815Z/work/out/stdout.txt` -> missing
- `AGENTS/tasks/compute_algebraic_multistep_20260217T055815Z/work/out/stderr.txt` -> missing
- `AGENTS/tasks/compute_algebraic_multistep_20260217T055815Z/review/*` -> no files
- `AGENTS/tasks/compute_algebraic_multistep_20260217T055815Z/work/report.md` and `.../work/report_plan.md` -> contain plan report only; no orchestration/debug prose.

Conclusion from artifacts: exploration/prose lines were not produced by repo task subprocess outputs.

## Evidence table: bad behavior -> source attribution
| Observed bad behavior | Attribution | Evidence |
|---|---|---|
| Orchestration prose (`I’ll locate...`, `I’m checking...`, etc.) | **External (C)** | No literal hits in runtime code; only historical/test text for `Explored` (`tests/regression/compute_algebraic_multistep.sh:14`). |
| Repo exploration messages (`Explored`, `Search ...`, read command narration) | **External (C)** | Runtime code prints marker-style lines, not narrated tool logs (`bin/a:675-699`, `bin/agenthub:1002-1008`, `bin/agenthub:884-940`). |
| Auto-prefill goal from broad prompt | **External (C)** | `bart --pick` does not call `request-set` (`bin/a:666-695`); `request-set` only updates field provided by caller (`bin/agenthub:818-865`). |
| Invent default symbolic problem and fill remaining fields | **External (C)** | No such logic in `bart`, `agenthub`, or skill run script; only per-step schema prompts and strict next-field guard (`bin/agenthub:800-802`, `:937-939`). |
| Chained multiple `request-set` + policy steps in one pass | **External initiator over repeated calls (C)** | `request-set` handles one field/call and exits (`bin/agenthub:803-817`, `:884-940`). |
| Potential repo contribution to weak guardrails | **Repo-side mitigation opportunity (A/B), not root cause** | Contract currently relies on caller discipline despite stop markers; no hard anti-autofill interlock at CLI boundary. |

## Current vs intended state machine (brief)
Current (repo):
1. `bart --pick 1` for compute starts task and returns first schema question.
2. Each `agenthub request-set --field <current_step>` updates one field and returns next question.
3. Final field triggers auto plan generation (plan-only) and returns `STOP_REASON=need_user_review`.

Intended UX contract:
1. Ask exactly one question.
2. Wait for user input.
3. Persist exactly one field.
4. Stop.

Gap:
- External orchestrator can still loop through multiple `request-set` calls without user pause; repo currently does not cryptographically/interaction-gate "one human turn -> one request-set call".

## Minimal fix recommendations (no implementation)
- Add a strict non-interactive guard in `agenthub request-set` for compute schema mode:
  - require explicit `--ack-stop-token <token>` generated from previous response, single-use per step.
- Add a "manual-only" latch in task state:
  - after each `request-set`, mark `awaiting_user_turn=true`; clear only when fresh user input is recorded by top-level entrypoint.
- In `bart --pick` compute path, print an explicit machine marker like `WAIT_FOR_USER_INPUT=true` and require that marker acknowledgment before next mutation call.
- Strengthen output sanitizer/validator at orchestrator boundary (repo-side defensive option): reject/tool-block assistant messages containing exploration/tool-trace tokens during schema collection.
- Keep `request-set` one-field semantics unchanged; add optional cooldown/lock file to prevent immediate chained updates from same process context.

## Regression tests to add
- `bart --pick 1` compute flow must emit `STOP_REASON=need_user_input` and no additional state mutations.
- Repeated immediate `request-set` calls without explicit ack token should fail with deterministic error.
- Ensure `request-set` still enforces `field == current_step` and exactly one field update per invocation.
- Ensure user-visible schema output contains no tool-trace/prose tokens (`Explored`, `Search`, `functions.exec_command`, etc.).
- End-to-end test that policy steps also obey one-step-per-user-turn contract.

