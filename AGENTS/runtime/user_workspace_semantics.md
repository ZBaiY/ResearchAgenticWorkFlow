# USER Workspace Semantics (B')

`USER/` is the canonical human-owned workspace. Agents do not write to `USER/` by default.
Promotion flow is: run skill -> review/stage in `GATE/staged/<task_id>/` -> user manually copies approved files into `USER/`.

## Stable semantics
- `paper/`: compilable manuscript unit (source `.tex`, bibliography, paper-local metadata).
- `slides/`: talk deliverables unit (editable slide source, optional pptx, notes).
- `notes/`: working notebook (research notes, planning, rough derivations).
- `src/`: approved runnable code (Python/Mathematica and helpers).
- `data/`: approved datasets or dataset manifests.
- `meta/` or `manifest/`: structured project/paper metadata and locks.

## Promotion target mappings (examples)
- `GATE/staged/<task_id>/<skill>/patches/patch.diff` -> apply manually to `USER/paper/`.
- `GATE/staged/<task_id>/<skill>/deliverable/src/*` -> `USER/src/python/<task_or_topic>/` or `USER/src/wolfram/<task_or_topic>/`.
- `GATE/staged/<task_id>/<skill>/paper_profile.json` -> `USER/paper/meta/paper_profile.json`.
- `GATE/staged/<task_id>/<skill>/review/refs.bib` -> `USER/paper/bib/<topic>.bib`.
- `GATE/staged/<task_id>/<skill>/deliverable/slides/*` -> `USER/slides/<talk_slug>/`.

## Future-structure guidance
Do not reorganize existing files automatically. If the current layout differs (for example `fig/` vs `paper/fig/`, or `manifest/` vs `meta/`), keep current content and converge gradually during manual promotions.
