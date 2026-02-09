# Agentic Research Workflow

This repository provides a project-local agentic workflow for research tasks (writing, literature scouting, computation, review), with the user always in control.

---

## Quick Start (Codex UI)

**Recommended interface: Codex UI.**

In Codex UI, shell commands must be prefixed with `!`.

```bash
!bart "search literature related to ULDM neutrino oscillations"
!bart "update project metadata based on current draft"
```

Core workflow:
1. Run `!bart "..."` with your request.
2. Default mode is suggest-only: review the recommended skill and start only what you approve.
3. Optional autopilot: `!bart --full-agent "..."` to route, start, and run automatically.
4. Review task outputs under `AGENTS/tasks/<task_id>/review/`.
5. Stage to `GATE/` only when explicitly enabled; promotion to `USER/` is always manual.
