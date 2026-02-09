# Get JCAP Style Package (Manual)

Direct style-package download links were not discovered reliably from the cached TeXclass snapshot.

Official URLs to use:

- JCAP TeXclass help page:
  https://jcap.sissa.it/jcap/help/JCAP_TeXclass.jsp
- JCAP author manual PDF:
  https://jcap.sissa.it/jcap/help/JCAP/TeXclass/DOCS/JCAP-author-manual.pdf

Manual steps:

1. Open the TeXclass help page and locate links for    `jcappub.sty` and any official JCAP template source.
2. Download those files into:
   `AGENTS/skills/jcap_writer/resources/`
3. For each downloaded file, create corresponding metadata JSON in:
   `AGENTS/skills/jcap_writer/resources/meta/<filename>.json`
   using fields: `url`, `fetched_at_utc`, `sha256`, `bytes`, `status`, `notes`.
