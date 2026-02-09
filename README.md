# Project-Local Agentic Research Workflow

This repository is a project-local workflow for controlled agent assistance. You stay in charge of decisions while agents help with literature scouting, writing, compute, and slide preparation in isolated task workspaces.

## Core Principles

- `USER/` is canonical. Agents never write to `USER/`.
- Agents operate under `AGENTS/` and may stage candidates only under `GATE/staged/`.
- Staging is optional and consent-based; final promotion into `USER/` is always manual.
- Rare exception: a skill may write to `USER/` only with a strong warning and exact explicit confirmation text.

## USER Workspace

`USER/` is the canonical workspace for manuscript, approved code, notes, slides, data, and metadata.
Agents do not update it during normal runs; they produce outputs under `AGENTS/` and optional staged packages under `GATE/staged/`.
You manually promote approved staged artifacts into `USER/`.
See `USER/README.md` for the local user-owned summary and `AGENTS/runtime/user_workspace_semantics.md` for the stable semantic contract and promotion target mappings.

## Workflow

1. `cd` into the project directory.
2. Open one or more terminal clients you prefer (Codex / Claude Code / Gemini).
3. State your intent in plain language.
4. The system suggests relevant skill(s).
5. Select a skill and answer only the missing questions.
6. The skill runs in a controlled workspace and produces review outputs.
7. Review the summary and report/patch/results.
8. If applicable, give explicit consent to export deliverables.
9. Give explicit consent to stage candidate packages into `GATE/staged/<task_id>/`.
10. Manually promote approved staged outputs into `USER/` (which remains authoritative).

Agents can stage candidates only; they cannot modify `USER/`. Any change in `USER/` happens only through manual user promotion.

## Failure / Unavailable Backends

If a backend or network dependency is unavailable, skills write diagnostics and placeholder summaries in task outputs/logs. Nothing is promoted automatically; you can retry later or stage diagnostics explicitly for review.

## What You Usually Touch

Most of the time you interact with your canonical content in `USER/`, then review concise outputs (report/patch/result summaries) from task runs, and only manually promote what you accept.

## Minimal Example

You say: “I want to scout literature on Floquet neutrino oscillations in ULDM.”  
The system suggests a literature skill, asks missing constraints, runs, and returns a report plus curated refs.  
If you approve, it stages to `GATE/staged/<task_id>/`; you then manually promote selected refs into `USER/`.
