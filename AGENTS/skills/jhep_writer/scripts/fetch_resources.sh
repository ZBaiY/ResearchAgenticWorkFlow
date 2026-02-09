#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES_DIR="$ROOT/resources"
META_DIR="$RES_DIR/meta"
STATUS_MD="$RES_DIR/README.md"
STYLE_HELP_MD="$RES_DIR/GET_THE_STYLE_PACKAGE.md"
UA="CodexCLI-JhepWriter/1.0 (+https://jhep.sissa.it)"

mkdir -p "$RES_DIR" "$META_DIR"

json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

write_meta() {
  local dest="$1"
  local url="$2"
  local fetched_at_utc="$3"
  local status="$4"
  local notes="${5:-}"
  local bytes="0"
  local sha256=""
  local meta_file="$META_DIR/$(basename "$dest").json"

  if [[ -f "$dest" ]]; then
    bytes="$(wc -c < "$dest" | tr -d ' ')"
    sha256="$(sha256_file "$dest")"
  fi

  cat > "$meta_file" <<EOF2
{
  "url": "$(json_escape "$url")",
  "fetched_at_utc": "$fetched_at_utc",
  "sha256": "$sha256",
  "bytes": $bytes,
  "status": "$status",
  "notes": "$(json_escape "$notes")"
}
EOF2
}

fetch_file() {
  local url="$1"
  local dest="$2"
  local notes="${3:-}"
  local fetched_at_utc
  local tmp_file="${dest}.part"

  fetched_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  rm -f "$tmp_file"

  if curl -L --fail --silent --show-error -A "$UA" "$url" -o "$tmp_file"; then
    mv "$tmp_file" "$dest"
    write_meta "$dest" "$url" "$fetched_at_utc" "ok" "$notes"
    FETCH_LOG+=("ok|$(basename "$dest")|$url")
  else
    rm -f "$tmp_file"
    write_meta "$dest" "$url" "$fetched_at_utc" "failed" "$notes"
    FETCH_LOG+=("failed|$(basename "$dest")|$url")
  fi
}

extract_style_links() {
  local html_file="$1"
  if [[ ! -f "$html_file" ]]; then
    return 0
  fi
  grep -Eoi 'https?://[^"<> ]*(jheppub\.sty|template[^"<> ]*\.tex|\.zip)' "$html_file" | sort -u || true
}

FETCH_LOG=()

# 1) JHEP TeXclass help page
fetch_file \
  "https://jhep.sissa.it/jhep/help/JHEP_TeXclass.jsp" \
  "$RES_DIR/jhep_texclass.html" \
  "JHEP TeXclass help page HTML snapshot"

# 2) JHEP author manual PDF
fetch_file \
  "https://jhep.sissa.it/jhep/help/JHEP/TeXclass/DOCS/JHEP-author-manual.pdf" \
  "$RES_DIR/jhep_author_manual.pdf" \
  "JHEP author manual PDF"

# 3) Optional style package files if official links are discoverable
STYLE_LINKS="$(extract_style_links "$RES_DIR/jhep_texclass.html")"
if [[ -n "$STYLE_LINKS" ]]; then
  while IFS= read -r link; do
    [[ -n "$link" ]] || continue
    base="$(basename "$link")"
    fetch_file "$link" "$RES_DIR/$base" "Style/template resource discovered from JHEP TeXclass help page"
  done <<< "$STYLE_LINKS"
  rm -f "$STYLE_HELP_MD"
else
  cat > "$STYLE_HELP_MD" <<EOF2
# Get JHEP Style Package (Manual)

Direct style-package download links were not discovered reliably from the cached TeXclass snapshot.

Official URLs to use:

- JHEP TeXclass help page:
  https://jhep.sissa.it/jhep/help/JHEP_TeXclass.jsp
- JHEP author manual PDF:
  https://jhep.sissa.it/jhep/help/JHEP/TeXclass/DOCS/JHEP-author-manual.pdf

Manual steps:

1. Open the TeXclass help page and locate links for \
   \`jheppub.sty\` and any official JHEP template source.
2. Download those files into:
   \`AGENTS/skills/jhep_writer/resources/\`
3. For each downloaded file, create corresponding metadata JSON in:
   \`AGENTS/skills/jhep_writer/resources/meta/<filename>.json\`
   using fields: \`url\`, \`fetched_at_utc\`, \`sha256\`, \`bytes\`, \`status\`, \`notes\`.
EOF2
fi

# Human-readable status document
{
  echo "# JHEP Writer Offline Resources Status"
  echo
  echo "- Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "- User-Agent: \`$UA\`"
  echo
  echo "## Results"
  for line in "${FETCH_LOG[@]}"; do
    status="${line%%|*}"
    rest="${line#*|}"
    file="${rest%%|*}"
    url="${rest#*|}"
    echo "- [$status] \`$file\` <- $url"
  done
  echo
  if [[ -f "$STYLE_HELP_MD" ]]; then
    echo "Style package note: \`resources/GET_THE_STYLE_PACKAGE.md\`"
  fi
  echo
  echo "Rerun command:"
  echo "\`bash AGENTS/skills/jhep_writer/scripts/fetch_resources.sh\`"
} > "$STATUS_MD"

exit 0
