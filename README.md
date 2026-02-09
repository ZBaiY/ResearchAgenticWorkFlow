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
2. From a normal shell, run `./bart "your request"` to enter the repo-local agent flow.
3. If needed, run `./bin/agent --client <codex|claude|gemini>` to bootstrap and open a client UI.
4. State your intent in plain language.
5. Use `./bart "..."` (or `./bin/agenthub suggest "..."`) to get relevant skill suggestions.
6. Select a skill and answer only the missing questions.
7. The skill runs in a controlled workspace and produces review outputs.
8. Review the summary and report/patch/results.
9. If applicable, give explicit consent to export deliverables.
10. Give explicit consent to stage candidate packages into `GATE/staged/<task_id>/`.
11. Manually promote approved staged outputs into `USER/` (which remains authoritative).

Agents can stage candidates only; they cannot modify `USER/`. Any change in `USER/` happens only through manual user promotion.

## Failure / Unavailable Backends

If a backend or network dependency is unavailable, skills write diagnostics and placeholder summaries in task outputs/logs. Nothing is promoted automatically; you can retry later or stage diagnostics explicitly for review.

## First Command of the Day

Run this once after entering the repo:

`./bart "your request"`

Optional: alias `bart='./bart'`

Permanent alias (zsh):
```sh
pwd
# add this line to ~/.zshrc using your repo path from pwd
alias bart='/ABSOLUTE/PATH/TO/REPO/bart'
source ~/.zshrc
```

## What You Usually Touch

Most of the time you interact with your canonical content in `USER/`, then review concise outputs (report/patch/result summaries) from task runs, and only manually promote what you accept.

## Minimal Example

You say: “I want to scout literature on Floquet neutrino oscillations in ULDM.”  
The system suggests a literature skill, asks missing constraints, runs, and returns a report plus curated refs.  
If you approve, it stages to `GATE/staged/<task_id>/`; you then manually promote selected refs into `USER/`.
