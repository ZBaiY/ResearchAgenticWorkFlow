---
OUTPUT POLICY (STRICT)
- Do NOT narrate. Do NOT write “I found / I’ll / Ran / Explored / Search…”.
- Do NOT echo shell scripts or commands (no “set -euo pipefail” or command blocks in output).
- Only print raw stdout/stderr of repo commands when necessary, and keep it minimal.
- For schema loops, print ONLY:
  REQUEST_STEP=...
  REQUEST_COMPLETE=...
  STOP_REASON=...
  <one question line + minimal example line>
- After ANY STOP_REASON, you MUST stop and ask the user. Forbidden: running additional commands in the same turn.
- Never use `set -x`.
- If you must run multiple commands, run them silently (redirect irrelevant output to /dev/null) and print only the required marker lines.
---

# Nature Communications Offline Resources Status

- Generated at: 2026-02-09T07:34:50Z
- User-Agent: `CodexCLI-NatureCommWriter/1.0 (+https://www.nature.com)`

## Results
- [failed] `ncomms_for_authors.html` <- https://www.nature.com/ncomms/for-authors
- [failed] `nature_reporting_standards.html` <- https://www.nature.com/nature-research/editorial-policies/reporting-standards

Template note: `resources/GET_LATEX_TEMPLATE.md`

Rerun command:
`bash AGENTS/skills/nature_comm_writer/scripts/fetch_resources.sh`
