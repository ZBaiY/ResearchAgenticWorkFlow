# compute_algebraic_multistep phase and latency audit

## 1) Expected state machine vs actual transitions

### Expected (contract)
- Phase 0: `bart` route/pick scaffolds task and stops.
- Phase 1: schema collection is one-field-per-turn (`goal -> inputs -> expected_outputs -> constraints -> preferred_formats`, then optional policy), stop after each field with `STOP_REASON=need_user_input`.
- Phase 2: plan is generated only on explicit `agenthub run --task <TASK_ID>`.
- Phase 3: human review loop.
- Phase 4: execution only on explicit `--execute`.

### Actual (current code paths)
- `./bart "..." --pick 1 --start` starts task and stops at schema input:
  - Observed output includes `REQUEST_STEP=goal`, `REQUEST_COMPLETE=false`, `STOP_REASON=need_user_input`.
  - No run/execute call in this path (`bin/a:701-708`).
- `agenthub request-set` updates exactly one field and enforces strict next-step (`bin/agenthub:800-802`, `bin/agenthub:818-865`).
- Divergence from expected Phase 2 trigger:
  - For `compute_algebraic_multistep`, when `request-set` reaches `done`, it auto-invokes planner subprocess (`agentctl run`) and emits plan markers immediately (`bin/agenthub:887-932`).
  - This enters plan phase without a separate explicit `run` command.

## 2) Root-cause layer attribution

### A) Auto-fill / multi-step chaining after one user answer
- Attribution: external orchestration/wrapper layer.
- Evidence:
  - `bart --pick/--start` path does not call `request-set` in a loop (`bin/a:679-708`).
  - `request-set` is one-field-per-call and exits (`bin/agenthub:803-817`, `bin/agenthub:884-940`).
  - Provenance scan found orchestration prose only in audits/tests, not runtime emitters (`rg` results in `AGENTS/review/*`, `tests/*`, not `bin/a`/`bin/agenthub` operational strings).

### B) Plan entered without explicit `run`
- Attribution: CLI core behavior in `request-set` done-branch for multistep.
- Evidence:
  - `bin/agenthub:887-932` calls `agentctl run` at schema completion and prints `PLAN_STATUS=READY_FOR_REVIEW`.

### C) Stop-contract bypass
- Stop marker emitted correctly for incomplete schema (`bin/agenthub:937-939`, and run gate `bin/agenthub:1361-1370`).
- Bypass occurs when downstream orchestrator ignores `STOP_REASON=need_user_input` and issues additional commands in same turn.

## 3) Static provenance and call-graph evidence

### Provenance scan
- No literal runtime hits for reported orchestration prose patterns (`I’ll locate...`, `prefill`, `filled the remaining...`, `Ran sed -n`, `Ran ls -la`, `random integral`) in operational CLI/skill files.
- Hits were in test/audit docs only (e.g., `tests/regression/compute_algebraic_multistep.sh:14`, `AGENTS/review/compute_multistep_schema_loop_regression_audit.md`).

### Call graph (relevant)
- `bart --pick/--start`:
  - task naming + template write + `agenthub start` (`bin/a:666-703`), then stop for compute (`bin/a:706-708`).
- `agenthub request-set`:
  - strict sequencing check (`bin/agenthub:800-802`), one field write (`bin/agenthub:818-865`), state emit (`bin/agenthub:884-940`).
- `agenthub run`:
  - compute preflight gate pauses when incomplete (`bin/agenthub:1361-1370`).
- skill script:
  - run script validates request and builds plan/exec depending on `COMPUTE_EXECUTE` (`AGENTS/skills/compute_algebraic_multistep/scripts/run.sh:55-160`, later plan/execute branching).

## 4) Task artifact inspection

- Latest inspected task: `AGENTS/tasks/compute_algebraic_multistep_20260217T085116Z`.
- Present files indicate plan/execute reports and step files under `work/src/steps`.
- `work/out/stdout.txt` and `work/out/stderr.txt` are absent for this task snapshot.
- No orchestration prose/tool-trace strings found in inspected task artifacts.

## 5) Latency analysis (~10s per schema turn)

### Measured local CLI timings (cold-normal)
- `agenthub start` (multistep): ~0.08s real.
- `request-set` goal/inputs/expected/constraints/preferred/policy_customize: ~0.04s each.
- final `request-set` (policy_overrides -> done -> auto-plan): ~0.11s.

### Ranked likely causes
1. **External orchestration overhead per turn (highest likelihood)**
   - Multiple tool/search/read actions between turns dominate latency, not CLI state mutation.
   - Consistent with reported `Search/Explored/sed/ls/cat` artifacts not originating from CLI.
2. **Wrapper-side logging/formatting/rendering latency (high)**
   - Tool-trace/prose generation and filtering in wrapper can add seconds independent of CLI call duration.
3. **Unintended extra command chaining in one turn (medium-high)**
   - Repeated `request-set` and optional run/plan calls serialized by orchestrator increase perceived per-prompt delay.
4. **CLI-side compute operations during schema (low)**
   - Only notable non-trivial branch is multistep auto-plan on done (`bin/agenthub:887-932`), but measured ~0.11s in this environment.
5. **Network / heavy FS scan in schema path (very low)**
   - No network calls in schema path; no repo-wide scan in `request-set` path.

### Verification steps (audit only)
- Time each orchestration stage separately at wrapper boundary (raw timestamps before/after every command dispatch).
- Capture exact command list per user turn; assert one command max in schema mode.
- Compare wrapper elapsed vs CLI elapsed (`/usr/bin/time -p ./bin/agenthub request-set ...`).
- Capture raw (pre-render) assistant stream to identify insertion point of exploration logs.

## 6) Minimal fix recommendations (no implementation)

1. Enforce orchestration state gate: after any `STOP_REASON=need_user_input`, allow exactly one user response -> one `request-set`, then stop.
2. Disallow orchestration command fan-out in schema mode: block repo exploration/tool commands and additional `request-set` calls in same turn.
3. Require explicit user intent tokens for phase transitions:
   - `RUN` required for plan generation (if maintaining contract strictly).
   - `READY` required before execute.
4. Keep CLI run gate for incomplete requests as terminal pause (`STOP_REASON=need_user_input`) and ensure wrapper cannot bypass it.
5. If contract requires Phase-2-only planning, remove/disable done-branch auto-plan (`bin/agenthub:887-932`) in a separate controlled change.
