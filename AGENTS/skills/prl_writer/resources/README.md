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

# PRL Writer Offline Resources Status

- Generated at: 2026-02-09T07:23:02Z
- User-Agent: `CodexCLI-PrlWriter/1.0 (+https://journals.aps.org)`

## Results
- [failed] `prl_info_for_contributors.html` <- https://prl.aps.org/info/infoL.html
- [failed] `aps_length_guide.html` <- https://journals.aps.org/authors/length-guide
- [failed] `revtex_home.html` <- https://journals.aps.org/revtex
- [failed] `revtex_faq.html` <- https://journals.aps.org/revtex/revtex-faq
- [failed] `aps_style_guide_authors.pdf` <- https://cdn.journals.aps.org/files/aps-author-guide.pdf
- [failed] `apsguide4-2.pdf` <- https://ctan.math.illinois.edu/macros/latex/contrib/revtex/aps/apsguide4-2.pdf
- [failed] `apstemplate.tex` <- https://ctan.math.illinois.edu/macros/latex/contrib/revtex/sample/aps/apstemplate.tex
- [failed] `revtex-tds.zip` <- https://ctan.math.illinois.edu/macros/latex/contrib/revtex.zip

If any entry is [failed], rerun:
`bash AGENTS/skills/prl_writer/scripts/fetch_resources.sh`
