# Research Agentic Workflow (Project Instance)

This repository is a **project-local instance** of an agentic research workflow.

Hard rule:
- Agents may write ONLY under `AGENTS/`
- `USER/` is the user-owned single source of truth (agents must not modify)
- `GATE/` is the manual merge gate (user-owned staging)

See directory contracts:
- `USER/README.md`
- `AGENTS/README.md`
- `GATE/README.md`


## Example Day-to-Day Workflow (Simulation)

This section illustrates the *intended* human-facing workflow. Most of the time, the user never looks at `AGENTS/tasks/`.

### 1. User works in the canonical workspace

The user’s daily focus is exclusively on:

- `USER/paper/` — LaTeX sources of the manuscript
- `USER/src/` — approved computation scripts (Python / Mathematica)
- `USER/fig/` — finalized figures referenced by the paper

Example:
```
vim USER/paper/floquet.tex
```

At this stage, the user is writing, editing, or reviewing science — not managing agents.

### 2. User delegates a bounded task to an agent

When assistance is useful (rewriting text, checking narrative clarity, running a computation), the user creates a task:

```
agentctl new rewrite_floquet_section
```

The user writes a concise request in:

```
AGENTS/tasks/<task_id>/request.md
```

describing *what* should be done and *what must not change*. The user does **not** browse other task internals.

### 3. Agent runs in the background

The agent is invoked, for example:

```
agentctl run prl_writer --task <task_id>
```

The agent may generate drafts, computations, logs, and reports — all confined to `AGENTS/tasks/<task_id>/`.

This layer exists for **auditability and reproducibility**, not for daily human attention.

### 4. User reviews only the merge candidate

When the agent finishes, the user copies the minimal deliverable into `GATE/`:

```
cp AGENTS/tasks/<task_id>/deliverable/patchset \
   GATE/patches/<task_id>
```

The user reviews **only** what is staged in `GATE/`:
- LaTeX diffs
- Script changes
- Short review notes

No other agent artifacts are considered.

### 5. User promotes accepted changes into USER/

After review, the user manually applies the patch to `USER/`:

```
git apply GATE/patches/<task_id>/patch.diff
latexmk -pdf USER/paper/main.tex
```

If accepted, the change becomes part of the canonical workspace.
`GATE/` is then cleaned.

### 6. Agent artifacts remain as audit trail

All detailed logs, intermediate attempts, and provenance information remain in `AGENTS/`.
They are consulted only if:
- a reviewer asks for clarification,
- a result must be reproduced,
- or an error needs forensic inspection.

### Core Principle

**The agent is a background laboratory assistant.  
`USER/` is the desk the researcher actually works at.  
`GATE/` is a short-lived review buffer.  
`AGENTS/` is the archive and insurance layer.**


## Literature Scouting Agent — Intended Usage Scenario

This section describes how the *literature scouting agent* is meant to be used in practice.
It is a **background intelligence tool**, not a literature manager and not part of the user’s daily workspace.

### When the scouting agent is invoked

The user invokes the literature scouting agent only at specific moments, for example:
- checking whether recent literature overlaps with a new idea,
- verifying coverage before submission,
- anticipating references a referee might cite against the work.

It is *not* used for continuous reading or maintaining a personal bibliography.

### 1. User initiates a scouting task

The user creates a task:

```
agentctl new literature_scout_uldm_neutrinos
```

The user writes a focused request in:

```
AGENTS/tasks/<task_id>/request.md
```

Typical content includes:
- the scientific topic,
- the time window (e.g. “2018–present”),
- explicit questions the scouting should answer,
- exclusions to avoid irrelevant review papers.

At this stage, the user does not browse other task files.

### 2. Agent performs background scouting

The agent searches relevant databases (e.g. arXiv, INSPIRE, ADS), collects candidate papers, and evaluates relevance.
All intermediate artifacts (PDFs, search logs, raw lists) remain confined to:

```
AGENTS/tasks/<task_id>/
```

This layer exists purely for auditability and reproducibility.

### 3. User reads only the scouting report

After completion, the user reads **one primary output**:

```
AGENTS/tasks/<task_id>/review/literature_scout_report.md
```

This report is an *intelligence brief*, not a dump of papers.
It typically contains:
- an executive summary,
- papers a referee is likely to cite,
- short relevance notes,
- identified gaps the current work fills.

Optionally, a curated BibTeX file is provided:

```
AGENTS/tasks/<task_id>/review/refs.bib
```

### 4. Promotion into USER (explicit and selective)

Only papers the user explicitly approves are promoted into the canonical workspace.
For example:

```
cp AGENTS/tasks/<task_id>/review/refs.bib USER/paper/bib/literature_scout.bib
```

No other scouting artifacts are moved into `USER/`.

### 5. Long-term role of scouting artifacts

All scouting details remain in `AGENTS/` as an audit trail.
They are consulted only if:
- a referee questions novelty,
- overlap claims must be justified,
- literature coverage needs to be re-verified.

### Core Principle

**The literature scouting agent answers:  
“Will a knowledgeable referee challenge this work based on existing literature?”  

It does not replace the user’s judgment, and it does not occupy the user’s daily attention.**
