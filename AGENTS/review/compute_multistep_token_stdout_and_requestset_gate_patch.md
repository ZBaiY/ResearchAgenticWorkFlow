# compute_multistep token stdout + request-set gate patch

## A) Provenance audit

### Emitters: `REVIEW_TOKEN_ISSUED`
- `bin/agenthub` (CLI runtime): previously emitted in plan-only branches (now removed).
- `tests/regression/compute_algebraic_multistep.sh:110` (regression guard pattern only).
- `AGENTS/review/compute_multistep_phase3_hardening_patch.md:10` (doc text).

### Emitters: `REVIEW_TOKEN`
- No current runtime stdout emitters in `bin/agenthub` or compute skill scripts.
- Present only in docs/tests text:
  - `tests/regression/compute_algebraic_multistep.sh:110`
  - `AGENTS/review/compute_multistep_phase3_gate_patch.md:19`
  - `AGENTS/review/silent_driver_policy_injection_postpatch_audit.md:10`

### Emitters: `PLAN_STATUS=READY_FOR_REVIEW`
- CLI runtime: `bin/agenthub:1454`, `bin/agenthub:1685`.
  - Call path 1: `agenthub run --task <id>` for `compute_algebraic_multistep` with no `--execute` (plan-only branch).
  - Call path 2: `agenthub plan-revise --task <id> --feedback ...` (re-plan branch).
- Skill runtime: `AGENTS/skills/compute_algebraic_multistep/scripts/run.sh:257` (plan-only skill output).
- Tests/docs: assertions and audit docs only.

### Emitters: `set -euo pipefail`
- Runtime script source headers (`bart`, `bin/agentctl`, `bin/agent`, `bin/ask`, `AGENTS/runtime/*.sh`, skill scripts) and tests.
- This is source code text, not a runtime marker printed by `agenthub` normal outputs.

### Emitter: `I’ll finalize this field, run plan-review-execute in sequence`
- No hits in repo source (`rg` returned none).

### Confirmation on `REVIEW_TOKEN_ISSUED=true`
- Current runtime (`./bin/agenthub`) no longer prints `REVIEW_TOKEN_ISSUED=true` on run paths.
- Remaining occurrences are test/doc text only.

## B) Minimal runtime patch applied

### Changed files
- `bin/agenthub`
- `tests/regression/compute_algebraic_multistep.sh`

### Runtime stdout hardening
- Removed plan-path stdout token line `REVIEW_TOKEN_ISSUED=true` from:
  - `cmd_run` multistep plan-only return block.
  - `cmd_plan_revise` plan-ready return block.
- Blocked execute output remains strictly:
  - `EXECUTION_ALLOWED=false`
  - `STOP_REASON=need_user_review`
  - `REVIEW_READY_FOR_EXECUTE=false`
  - `HINT=Review required.`

## C) request-set non-plan guarantee

### Regression check added
- `tests/regression/compute_algebraic_multistep.sh:110-113`
  - On final `agenthub request-set ... --field policy_overrides ...` completion output, assert absence of:
    - `PLAN_STATUS=`
    - `REVIEW_TOKEN_ISSUED=`
    - `REVIEW_TOKEN=`
  - Still asserts:
    - `REQUEST_STEP=done`
    - `REQUEST_COMPLETE=true`
    - `STOP_REASON=request_complete_waiting_user_run`

### Behavior result
- `agenthub request-set` completion remains one command/one field and emits only request completion markers + completion sentence.
- No plan markers emitted from `request-set` completion output.

## Tests run
- `tests/regression/compute_algebraic_multistep.sh` ✅
- `tests/regression/compute_request_completion.sh` ✅
