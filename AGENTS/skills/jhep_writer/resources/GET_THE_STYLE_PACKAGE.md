# Get JHEP Style Package (Manual)

Direct style-package download links were not discovered reliably from the cached TeXclass snapshot.

Official URLs to use:

- JHEP TeXclass help page:
  https://jhep.sissa.it/jhep/help/JHEP_TeXclass.jsp
- JHEP author manual PDF:
  https://jhep.sissa.it/jhep/help/JHEP/TeXclass/DOCS/JHEP-author-manual.pdf

Manual steps:

1. Open the TeXclass help page and locate links for    `jheppub.sty` and any official JHEP template source.
2. Download those files into:
   `AGENTS/skills/jhep_writer/resources/`
3. For each downloaded file, create corresponding metadata JSON in:
   `AGENTS/skills/jhep_writer/resources/meta/<filename>.json`
   using fields: `url`, `fetched_at_utc`, `sha256`, `bytes`, `status`, `notes`.
