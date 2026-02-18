Section 1: Current state machine (diagram in bullet form)

- Entry: `bart "<query>"` (router only)
  - `bin/a:644-646` -> calls `print_suggestions(...)` and exits.
  - `print_suggestions` emits candidates + `PICK_REQUIRED=true` + `RECOMMENDED_SKILL=...` (`bin/a:443-456`).

- Entry: `bart "<query>" --pick N`
  - Pick parsing: `normalize_pick_text` (`bin/a:433-440`), apply index (`bin/a:651-659`).
  - Task naming via `agenthub task-name` (`bin/a:666-669`) -> `default_task_name` in `agenthub` (`bin/agenthub:1404-1406`).
  - Request template scaffold file under `AGENTS/requests/<task>.md` (`bin/a:384-430`, call at `bin/a:673`).
  - Outputs and stop: `START_PENDING=true`, `SELECTED_SKILL`, `TASK_NAME` (`bin/a:690-694`).

- Entry: `bart "<query>" --pick N --start`
  - Runs `agenthub start` (`bin/a:696-699`) then prints stop markers (`bin/a:701-705`).
  - `agenthub start` creates task dir + `meta.json` (`bin/agenthub:832-857`) and prints:
    - `TASK=...`
    - for compute skills: `REQUEST_JSON`, `REQUEST_PROGRESS`, `REQUEST_STEP=goal`, `REQUEST_COMPLETE=false`, first prompt (`bin/agenthub:858-874`).

- Entry: `bart "<query>" --pick N --run`
  - Executes start first (`bin/a:696-699`).
  - Compute guard checks `start_out` marker; if `REQUEST_COMPLETE=false`, stops and prints:
    - `STARTED=true`, `REQUEST_COMPLETE=false`, `REQUEST_STEP=...` (`bin/a:707-714`).
  - Otherwise invokes `agenthub run` (`bin/a:716-727`).

- Entry: `agenthub request-set --task <id> --field <f> --value|--file`
  - Single field per call (`bin/agenthub:700-718` + value/file validation at `bin/agenthub:716-718`).
  - Writes one field into `request.json` (`bin/agenthub:731-785`), computes next step (`bin/agenthub:656-678`, `bin/agenthub:681-697`), prints `REQUEST_STEP` / `REQUEST_COMPLETE` (`bin/agenthub:804-810`).

- Entry: `agenthub run --task <id>`
  - Computes task skill (`bin/agenthub:1202-1211`).
  - Compute preflight gate:
    - `is_compute_skill` (`bin/agenthub:581-583`)
    - request completeness check (`bin/agenthub:610-632`)
    - if incomplete: writes `review/need_input.md` (`bin/agenthub:635-653`), emits pause markers, exits `0` (`bin/agenthub:1226-1238`).
  - If complete: spawns skill subprocess (`bin/agenthub:1244-1259`).
  - Subprocess nonzero -> exception path -> `error.md` / `SEE=` / `EXIT=nonzero` (`bin/agenthub:1260-1263`, `bin/agenthub:1297-1304`, `bin/agenthub:917-920`, `bin/agenthub:1156-1161`).

- Compute skill runners (`compute_*`)
  - `compute_algebraic`: missing/invalid request -> paused markers + `need_input.md` + exit `0` (`AGENTS/skills/compute_algebraic/scripts/run.sh:35-83`, `:121-169`).
  - `compute_numerical`: same pattern (`AGENTS/skills/compute_numerical/scripts/run.sh:35-83`, `:120-167`).
  - `compute_algebraic_multistep`: same fallback pattern (`AGENTS/skills/compute_algebraic_multistep/scripts/run.sh:30-53`, `:102-120`).

Section 2: Intended state machine (diagram in bullet form)

- Router: recommend only; user picks; STOP.
- After pick/start for compute: enter schema collection mode immediately with exactly one next question.
- One-field-per-turn only:
  - ask one field
  - persist one field
  - STOP
  - ask next field
  - no bulk filling/inference.
- Run gate:
  - if schema incomplete -> pause state (not error), emit `REQUEST_STEP`, no skill subprocess.
  - execute only when `request_complete=true`.
- Missing schema must be workflow state, never execution failure semantics.
- No run-steering continuation hints.

Section 3: Divergence points (file:line references)

1) Post-pick run steering text in observed interaction
- No such text is emitted by repo CLI binaries.
- `bart --pick` output is only `START_PENDING=true`, `SELECTED_SKILL`, `TASK_NAME` (`bin/a:690-694`).
- Therefore the sentence “If you want, I can run it now (--run)” is not from `bin/a`/`bin/agenthub`; it is outside these CLI outputs.

2) Schema does not auto-start on plain `--pick`
- `bart --pick` path does not call `agenthub start`; it returns at `bin/a:690-694`.
- First schema question is only produced by `agenthub start` (`bin/agenthub:858-874`) or preflight pause in `agenthub run` (`bin/agenthub:1226-1238`).
- `request_progress.json` is not consulted at selection-only branch (`bin/a:690-694`).

3) Why bulk fill is possible
- `request-set` updates exactly one field per invocation (`bin/agenthub:700-718`, `:731-785`).
- But there is no turn-level guard requiring human response between invocations; repeated scripted calls are allowed.
- `--value`/`--file` accepts arbitrary payload for the selected field (`bin/agenthub:716-718`, `:720-729`), enabling external automation to chain all fields rapidly.

4) Why run can still proceed after minimal input in some scenarios
- `request_preflight_status` checks only core required fields (`compute_next_step`) (`bin/agenthub:567-578`, `:625-632`).
- For multistep, policy prompts are tracked by `next_step_for_multistep` during `request-set` (`bin/agenthub:656-678`) but are not part of run gate completeness.
- Result: run may execute once core 5 fields are complete even if optional policy question loop was not finished.

5) Missing-schema error behavior
- Current `agenthub run` preflight returns paused state and does not spawn subprocess when incomplete (`bin/agenthub:1226-1238`).
- Compute runners also fallback to paused state with exit `0` (`compute_algebraic` `:35-83`, `:121-169`; `compute_numerical` `:35-83`, `:120-167`; multistep `:30-53`, `:102-120`).
- `error.md`/`EXIT=nonzero` now occurs only when subprocess actually runs and fails (`bin/agenthub:1260-1263`, `:1297-1304`, `:1156-1161`).

6) Continuation-token surfaces
- No runtime `NEXT_*`, `RUN_COMMAND`, or `RUN_PENDING` emissions found in `bin/*` current code.
- `bin/ask` currently emits `START_PENDING=true` and no `RUN_PENDING` (`bin/ask:62-65`).
- Search confirms no active runtime `NEXT_*`/`RUN_COMMAND` strings outside tests.

Section 4: Minimal structural fixes required (no implementation)

1) Enforce schema-first immediately after pick for compute
- If contract requires pick alone to enter schema mode, `bart --pick` branch must trigger start-equivalent output for compute skills instead of stopping at `START_PENDING` only.
- Minimal structural location: `bin/a` selection-only branch (`bin/a:690-694`).

2) Add strict turn gating for request-set progression
- Prevent multi-step auto-fill by requiring one-step-at-a-time progression tied to current `request_progress.json` step and rejecting non-current fields.
- Minimal structural location: `cmd_request_set` validation path (`bin/agenthub:700-715`).

3) Decide and codify multistep run readiness rule
- If policy Q&A must be completed before any run, include policy step completion in preflight gate.
- Minimal structural location: `request_preflight_status` (`bin/agenthub:610-632`) and/or dedicated readiness function.

4) Keep non-error pause semantics as the only incomplete-schema path
- Preserve current behavior where incomplete schema exits `0`, writes `need_input.md`, emits `REQUEST_STEP`, and avoids subprocess spawn.
- Guard location already present: `bin/agenthub:1226-1238`; keep as authoritative.
