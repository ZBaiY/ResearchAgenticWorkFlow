# compute_algebraic_multistep Phase2->Phase4 autorun audit

## 1) Timeline reconstruction (expected vs actual)

### Expected state machine
- Phase 1 (schema): one field per turn, stop with `STOP_REASON=need_user_input`.
- Phase 2 (plan): `agenthub run --task <TASK_ID>` (no `--execute`) produces plan-only and stops with:
  - `PLAN_STATUS=READY_FOR_REVIEW`
  - `EXECUTION_ALLOWED=false`
  - `STOP_REASON=need_user_review`
- Phase 3 (human review): user reviews/iterates plan; explicit review acknowledgement is required.
- Phase 4 (execute): only after explicit human confirmation and explicit execute command.

### Actual sequence (from reported log; treated as ground truth)
1. `agenthub run --execute` invoked.
2. CLI correctly blocks with review gate (`need_user_review`).
3. System then automatically searches for/decides to run `review-accept`.
4. System automatically runs `agenthub review-accept --task ...`.
5. System immediately re-runs `agenthub run --execute`.

This sequence is an auto-advance from Phase 2 gate to Phase 4 trigger without explicit human confirmation in that turn.

## 2) Layer attribution table

| Layer | Can cause reported auto-advance? | Evidence | File:line |
|---|---|---|---|
| `bin/agenthub` (CLI) | **Partially** (allows execution once latch is set) but does **not** auto-chain commands | `--execute` is only read from explicit CLI arg; no internal self-invocation of `review-accept`/second run. | `bin/agenthub:1706`, `bin/agenthub:1360-1362`, `bin/agenthub:1664-1671` |
| `bin/a` (`bart`) | **No** for this exact sequence unless caller uses explicit autopilot mode | Normal `--pick/--start/--run` path does not append `--execute`; just forwards to one `agenthub run`. | `bin/a:726-734` |
| `bin/a --full-agent` | **Yes (different mode)** can auto-start+run, but not observed sequence unless explicitly enabled | `--full-agent` is dangerous autopilot and auto-runs start+run; cannot be combined with `--pick/--skill`. | `bin/a:596-599`, `bin/a:616-623`, `bin/a:472-535` |
| `bin/agentctl` | **No** | Dispatches one skill run; no logic to call `review-accept` or rerun execute. | `bin/agentctl` (single-run dispatcher; no review command handling) |
| Multistep skill `run.sh` | **No** for chaining | Script responds to `COMPUTE_EXECUTE`; does not call `agenthub review-accept` or recursively invoke `agenthub run`. | `AGENTS/skills/compute_algebraic_multistep/scripts/run.sh:7`, `:255-260`, `:262+` |
| `AGENTS/runtime/*` helpers | **No** for this chain | No runtime helper consuming `STOP_REASON`/`HINT` and dispatching follow-up CLI commands. | `AGENTS/runtime/*` search results (no consumer hits) |
| Regression tests | **No in production**, **Yes in tests only** | Tests intentionally chain multiple commands (`request-set`, `review-accept`, `--execute`) but are not runtime entrypoints. | `tests/regression/compute_algebraic_multistep.sh:160-191` |
| External orchestrator/wrapper | **Yes (most likely)** | Reported behavior includes narrative/tool-driving steps (“searching”, “found”, immediate rerun) not emitted by repo CLI. | Provenance scans below; no runtime emitters found |

## 3) Auto-continue surfaces and consumers

### Surfaces emitted by CLI
- `STOP_REASON=need_user_input`
- `STOP_REASON=request_complete_waiting_user_run`
- `STOP_REASON=need_user_review`
- `HINT=Review plan first, then acknowledge with review-accept.`
- `REVIEW_READY_FOR_EXECUTE=false/true`

### In-repo consumers of these surfaces
- **No runtime consumer** found that parses these markers and auto-dispatches follow-up commands.
- Marker parsing exists in tests and helper scripts only (assertions/parsing), not production control flow.

### Security implication
- These markers are machine-parseable and can be consumed by an external wrapper/orchestrator that decides to auto-continue. The repository itself does not contain that continuation loop.

## 4) Provenance scan (mandatory)

### Required patterns searched
- `review-accept`
- `need_user_review`
- `REVIEW_READY_FOR_EXECUTE`
- `--execute`
- `STOP_REASON=`
- `HINT=`
- orchestration verbs (`Search`, `Explored`, `Ran`, etc.)
- auto-advance terms (`auto continue/advance/resume/next`)

### Findings
- `review-accept` appears in:
  - `bin/agenthub` parser/handler/output only (no auto-caller).
  - regression tests that explicitly invoke it.
- `--execute` appears in:
  - CLI parser and explicit flag handling in `bin/agenthub`.
  - wrappers/tests where explicitly provided.
- `STOP_REASON` and `HINT` appear as output markers in `bin/agenthub`, with no internal dispatch based on them.
- Orchestration narrative strings (`Explored`, `Search ...`, `Ran ...`, “I found...”, “immediately rerunning...”) have no runtime-source hits in CLI/skill scripts; hits are in tests/audits/docs.

## 5) Internal “assistant driver” check

### Result
- No repo-internal assistant driver was found that emits the observed narrative lines and then issues chained commands based on marker outputs.
- `bin/ask` is a lightweight suggester; it does not run tasks or execute follow-up commands.
  - It prints a `HINT=Request template ...` only. (`bin/ask:62-65`)

### Evidence
- String-provenance search found orchestration-style narration in test/audit text, not in runtime command paths.
- No file under `bin/` or `AGENTS/runtime/` contains a command loop reacting to `STOP_REASON` or `HINT` by running `review-accept` then `--execute`.

## 6) Timing/latency and noise angle (secondary)

### Findings
- No background polling loop in schema/review CLI paths.
- Only `time.sleep(1)` found in `bin/agenthub` is task-name collision handling (`reserve_task_id`), not phase progression logic.
- No built-in “tool-use logger” in runtime that prints “Explored/Search/Ran ...” narratives.

### Attribution
- Reported latency spikes/noisy narration are most consistent with external orchestrator behavior (extra searches/reads/command-chaining between user turns), not repo CLI core.

## 7) Most likely root causes (ranked)

1. **External orchestrator auto-continue policy** consumes review gate output and auto-issues `review-accept` + second `--execute`.  
   Confidence: **0.94**
2. **Repo-side hardening gap**: execution gate requires latch but does not require proof of explicit user confirmation in same turn/session boundary; external caller can still set latch immediately.  
   Confidence: **0.78**
3. **Accidental use of `--full-agent` mode** could auto-run phases, but this is less consistent with the exact observed `review-accept` chain and requires explicit flag.  
   Confidence: **0.22**

## 8) Minimal no-patch recommendations (for later)

1. Add a stricter execute precondition in CLI: `review-accept` should require an explicit review context marker (or user-confirmed token) that cannot be auto-satisfied by simple immediate command chaining.
2. Bind `review-accept` to human-turn acknowledgement semantics (short-lived nonce or explicit interactive confirm mode) so external automation cannot silently advance in same turn.
3. Remove/neutralize actionable hint text in blocked execute outputs if wrappers are known to parse hints as instructions.
4. Add regression coverage for “blocked execute must not be followed by auto-review-accept/auto-rerun within same orchestrated turn” at integration boundary.
5. Keep plan-only default and latch reset behavior; do not relax gate semantics.

## 9) Explicit uncertainty
- This audit cannot inspect external orchestration code outside the repository; attribution to external wrapper behavior is based on (a) absence of internal auto-chain logic, (b) explicit CLI flag-driven execute behavior, and (c) provenance mismatch for narrative logs.
