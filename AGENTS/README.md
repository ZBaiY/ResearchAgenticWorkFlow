# AGENTS/ (Writable sandbox)

All agent outputs MUST land here.

Structure:
- tasks/<task_id>/: each invocation creates a task folder
- skills/: reusable skills (prompt + schema + runner + checks)
- runtime/: helper scripts (dispatch, env probe, etc.)
- cache/: downloaded papers/pdf/web snapshots
