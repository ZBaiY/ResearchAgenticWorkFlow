# Agentic Research Workflow

Project-local workflow for research tasks (writing, literature scouting, computation, review) with the user in control.

1. `cd` into this repo and open Codex UI (recommended).
2. In Codex UI, run shell commands with `!`.
3. Route requests with quotes: `!./bart "<free text request>"`.
4. `./bart` is suggest-only by default: it prints ranked candidates and requires an explicit pick.
5. One-step start+run: `!./bart "<request>" --pick 1 --run` (safe default approval is `--no`).
6. Use `--yes` only when you want auto-approval for staging prompts; USER writes still require explicit `--write-user` on `agenthub`.
7. Review outputs in `AGENTS/tasks/<task_id>/review/` and staged files in `GATE/staged/<task_id>/`.
8. `USER/` is canonical and is never auto-written by agents; promotion to `USER/` is always manual.
9. Optional dangerous mode: `!./bart --full-agent "<request>"` (auto-picks and executes).
10. If you want zero agent flow, do not run `./bart` or `./bin/agenthub`; use your tools directly.
