# Agentic Research Workflow

Project-local workflow for research tasks (writing, literature scouting, computation, review) with the user in control.

1. `cd` into this repo and open Codex UI (recommended).
2. In Codex UI, run shell commands with `!`.
3. Route requests with quotes: `!bart "<free text request>"`.
4. `!bart` is suggest-only by default: it prints ranked candidates and requires an explicit pick.
5. One-step start+run: `!bart "<request>" --pick 1 --run`.
6. Successful runs always stage to `GATE/staged/<task_id>/<skill>/...`.
7. Default mode (`AGENT_MODE=off`) never auto-promotes; promotion requires explicit confirmation: `PROMOTE_TO_USER? [y/N]`.
8. Canonical promote command is `./AGENTS/runtime/promote_to_user.sh --task <task_id>`.
9. Global mode can be enabled explicitly with `./bin/agenthub run ... --agent-mode --auto-promote-user`.
10. In non-interactive runs, promotion requires `--yes --allow-user-write-noninteractive`; otherwise promotion is skipped.
11. `USER/` is canonical and is never auto-written unless explicitly promoted.
12. Optional dangerous routing mode: `!./bart --full-agent "<request>"` (auto-picks and executes).
13. If you want zero agent flow, do not run `./bart` or `./bin/agenthub`; use your tools directly.

Example flow:
- `!bart "update metadata" --pick 1 --start`
- `!bin/agenthub run --task <task_id> --yes`
- respond to `PROMOTE_TO_USER? [y/N]` or run `./bin/agenthub promote --task <task_id>` later.
