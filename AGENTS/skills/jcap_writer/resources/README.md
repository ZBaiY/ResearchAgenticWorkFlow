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

# JCAP Writer Offline Resources Status

- Generated at: 2026-02-09T07:26:17Z
- User-Agent: `CodexCLI-JcapWriter/1.0 (+https://jcap.sissa.it)`

## Results
- [failed] `jcap_texclass_help.html` <- https://jcap.sissa.it/jcap/help/JCAP_TeXclass.jsp
- [failed] `JCAP-author-manual.pdf` <- https://jcap.sissa.it/jcap/help/JCAP/TeXclass/DOCS/JCAP-author-manual.pdf

Style package note: `resources/GET_THE_STYLE_PACKAGE.md`

Rerun command:
`bash AGENTS/skills/jcap_writer/scripts/fetch_resources.sh`
