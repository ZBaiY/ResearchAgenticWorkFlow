#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES_DIR="$ROOT/resources"
META_DIR="$RES_DIR/meta"
STATUS_MD="$RES_DIR/README.md"
TEMPLATE_HELP_MD="$RES_DIR/GET_LATEX_TEMPLATE.md"
UA="CodexCLI-NatureCommWriter/1.0 (+https://www.nature.com)"

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

extract_template_zip_url() {
  local html_file="$1"
  if [[ ! -f "$html_file" ]]; then
    return 0
  fi

  # Restrict to official hosts only.
  grep -Eoi 'https?://(www\.)?(nature\.com|cdn\.nature\.com|media\.nature\.com)[^"<> ]*\.zip' "$html_file" | head -n 1 || true
}

FETCH_LOG=()

fetch_file \
  "https://www.nature.com/ncomms/for-authors" \
  "$RES_DIR/ncomms_for_authors.html" \
  "Nature Communications for-authors page snapshot"

fetch_file \
  "https://www.nature.com/nature-research/editorial-policies/reporting-standards" \
  "$RES_DIR/nature_reporting_standards.html" \
  "Nature research reporting standards snapshot"

TEMPLATE_URL="$(extract_template_zip_url "$RES_DIR/ncomms_for_authors.html")"
if [[ -n "$TEMPLATE_URL" ]]; then
  fetch_file "$TEMPLATE_URL" "$RES_DIR/nature-latex-template.zip" "Nature LaTeX template archive discovered from official page"
  rm -f "$TEMPLATE_HELP_MD"
else
  cat > "$TEMPLATE_HELP_MD" <<EOF2
# Get Nature LaTeX Template (Manual)

A direct official Nature-hosted template ZIP link was not confidently discovered from the cached page.

Official URLs to check:

- Nature Communications for authors:
  https://www.nature.com/ncomms/for-authors
- Nature research editorial and reporting standards:
  https://www.nature.com/nature-research/editorial-policies/reporting-standards

Manual steps:

1. Open the official for-authors page and locate the Nature LaTeX template link.
2. Download the official ZIP into:
   \`AGENTS/skills/nature_comm_writer/resources/nature-latex-template.zip\`
3. Add metadata JSON:
   \`AGENTS/skills/nature_comm_writer/resources/meta/nature-latex-template.zip.json\`
   with fields \`url\`, \`fetched_at_utc\`, \`sha256\`, \`bytes\`, \`status\`, \`notes\`.
EOF2
fi

{
  echo "# Nature Communications Offline Resources Status"
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
  if [[ -f "$TEMPLATE_HELP_MD" ]]; then
    echo
    echo "Template note: \`resources/GET_LATEX_TEMPLATE.md\`"
  fi
  echo
  echo "Rerun command:"
  echo "\`bash AGENTS/skills/nature_comm_writer/fetch_resources.sh\`"
} > "$STATUS_MD"

exit 0
