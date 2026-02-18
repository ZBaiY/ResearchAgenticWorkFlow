# Silent Driver Policy Injection Audit

## 1) Coverage audit

Modified files:
- AGENTS/policies/silent_driver_output_policy.md
- AGENTS/skills/compute_algebraic/README.md
- AGENTS/skills/compute_algebraic/prompts/prompt.md
- AGENTS/skills/compute_algebraic/templates/request.md
- AGENTS/skills/compute_algebraic_multistep/README.md
- AGENTS/skills/compute_algebraic_multistep/prompts/prompt.md
- AGENTS/skills/compute_numerical/README.md
- AGENTS/skills/compute_numerical/prompts/prompt.md
- AGENTS/skills/compute_numerical/templates/request.md
- AGENTS/skills/diffpack/prompts/prompt.md
- AGENTS/skills/jcap_writer/prompts/README.md
- AGENTS/skills/jcap_writer/prompts/prompt.md
- AGENTS/skills/jcap_writer/resources/README.md
- AGENTS/skills/jhep_writer/prompts/README.md
- AGENTS/skills/jhep_writer/prompts/prompt.md
- AGENTS/skills/jhep_writer/resources/README.md
- AGENTS/skills/latex_writer/prompts/README.md
- AGENTS/skills/latex_writer/prompts/prompt.md
- AGENTS/skills/literature_scout/prompts/prompt.md
- AGENTS/skills/nature_comm_writer/prompts/README.md
- AGENTS/skills/nature_comm_writer/prompts/prompt.md
- AGENTS/skills/nature_comm_writer/resources/README.md
- AGENTS/skills/paper_profile_update/prompts/prompt.md
- AGENTS/skills/prd_writer/prompts/README.md
- AGENTS/skills/prd_writer/prompts/prompt.md
- AGENTS/skills/prl_writer/prompts/README.md
- AGENTS/skills/prl_writer/prompts/prompt.md
- AGENTS/skills/prl_writer/resources/README.md
- AGENTS/skills/referee_redteam_prl/prompts/prompt.md
- AGENTS/skills/slide_preparation/prompts/prompt.md
- AGENTS/skills/slide_preparation/templates/deck_outline.md.tpl
- AGENTS/skills/slide_preparation/templates/figure_plan.md.tpl
- AGENTS/skills/slide_preparation/templates/speaker_notes.md.tpl

Assumptions / scope checks:
- Runtime prompt/template sources are under `AGENTS/skills/**/prompts/*`, `AGENTS/skills/**/templates/*`, and skill `README.md` files that may be consulted as instructions.
- No additional repo-level system prompt file was discovered beyond these skill-scoped sources.
- Regression scripts under `tests/` remain tests-only; no runtime path executes them automatically.

## 2) Failure mode audit (human-in-the-loop)

Places STOP_REASON can still be ignored by external driver:
- Any consumer that parses marker lines and auto-runs follow-up commands without waiting for user turn.
- Repo emits strict markers, but cannot force external wrapper behavior.

Remaining actionable hint text that may be misread:
- `bin/agenthub` blocked execute path prints: `Review plan. When ready, run review-accept with token.`
- `bin/agenthub` done-schema path prints: `Say continue and we will start to plan.`

Ambiguous wording:
- `continue` wording may be interpreted as immediate permission by an external driver.
- No remaining `continue to run` variant was intentionally reintroduced in prompt/template sources.

Potential one-turn command chaining surfaces:
- Runtime CLI does not contain an internal multi-command loop for schema progression.
- Regression scripts chain many commands by design (tests-only), e.g. `tests/regression/compute_algebraic_multistep.sh`.

## 3) Ambiguity audit

Prompt/template wording that could permit implicit progression:
- No newly injected policy block permits auto-prefill/default random examples; it explicitly forbids post-STOP automatic commands.
- Existing non-policy prompt text in legacy skill docs may still contain imperative wording; these were not behavior changes in this patch.

Prefill/default risks:
- No policy insertion introduced prefill/default permissions.
- Existing runtime behavior should still be validated separately against schema-loop tests for compute skills.

## 4) Regression test suggestions (not implemented here)

Suggested grep-based runtime-output guard:
- Fail if outputs contain any of: `Ran `, `Explored`, `set -euo pipefail`, `to=functions.exec_command`, `tool_uses`.

Suggested review-gate integrity guard:
- Fail if execute succeeds without prior valid review-ready latch/token acceptance.
- Fail if `STOP_REASON=need_user_review` is followed by automatic `review-accept` + `--execute` in the same orchestrated turn.
