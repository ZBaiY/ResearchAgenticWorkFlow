#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES_DIR="$ROOT/resources"
META_DIR="$RES_DIR/meta"
STATUS_MD="$RES_DIR/README.md"
UA="CodexCLI-PrlWriter/1.0 (+https://journals.aps.org)"

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

  cat > "$meta_file" <<EOF
{
  "url": "$(json_escape "$url")",
  "fetched_at_utc": "$fetched_at_utc",
  "sha256": "$sha256",
  "bytes": $bytes,
  "status": "$status",
  "notes": "$(json_escape "$notes")"
}
EOF
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

extract_first_pdf_url() {
  local html_file="$1"
  local base="$2"
  local abs rel
  if [[ ! -f "$html_file" ]]; then
    return 0
  fi
  abs="$(grep -Eoi 'https?://[^"'"'"'<> ]+\.pdf' "$html_file" | head -n 1 || true)"
  if [[ -n "$abs" ]]; then
    printf '%s' "$abs"
    return 0
  fi
  rel="$(grep -Eoi 'href="[^"]+\.pdf"' "$html_file" | sed -E 's/^href="//; s/"$//' | head -n 1 || true)"
  if [[ -n "$rel" ]]; then
    if [[ "$rel" =~ ^https?:// ]]; then
      printf '%s' "$rel"
    elif [[ "$rel" =~ ^/ ]]; then
      printf '%s%s' "$base" "$rel"
    else
      printf '%s/%s' "$base" "$rel"
    fi
  fi
}

extract_first_zip_url() {
  local html_file="$1"
  local base="$2"
  local abs rel
  if [[ ! -f "$html_file" ]]; then
    return 0
  fi
  abs="$(grep -Eoi 'https?://[^"'"'"'<> ]+\.zip' "$html_file" | head -n 1 || true)"
  if [[ -n "$abs" ]]; then
    printf '%s' "$abs"
    return 0
  fi
  rel="$(grep -Eoi 'href="[^"]+\.zip"' "$html_file" | sed -E 's/^href="//; s/"$//' | head -n 1 || true)"
  if [[ -n "$rel" ]]; then
    if [[ "$rel" =~ ^https?:// ]]; then
      printf '%s' "$rel"
    elif [[ "$rel" =~ ^/ ]]; then
      printf '%s%s' "$base" "$rel"
    else
      printf '%s/%s' "$base" "$rel"
    fi
  fi
}

FETCH_LOG=()

# A-D: APS/PRL HTML snapshots
fetch_file "https://prl.aps.org/info/infoL.html" "$RES_DIR/prl_info_for_contributors.html" "PRL information for contributors snapshot"
fetch_file "https://journals.aps.org/authors/length-guide" "$RES_DIR/aps_length_guide.html" "APS authors length guide snapshot"
fetch_file "https://journals.aps.org/revtex" "$RES_DIR/revtex_home.html" "APS REVTeX page snapshot"
fetch_file "https://journals.aps.org/revtex/revtex-faq" "$RES_DIR/revtex_faq.html" "APS REVTeX FAQ snapshot"

# E: APS style guide PDF (discover from APS pages first, fallback to known APS path)
STYLE_URL="$(extract_first_pdf_url "$RES_DIR/aps_length_guide.html" "https://journals.aps.org" || true)"
if [[ -z "$STYLE_URL" && -f "$RES_DIR/revtex_home.html" ]]; then
  STYLE_URL="$(extract_first_pdf_url "$RES_DIR/revtex_home.html" "https://journals.aps.org" || true)"
fi
if [[ -z "$STYLE_URL" ]]; then
  STYLE_URL="https://cdn.journals.aps.org/files/aps-author-guide.pdf"
fi
fetch_file "$STYLE_URL" "$RES_DIR/aps_style_guide_authors.pdf" "APS journals style/author guide PDF from APS-hosted URL"

# F/G: CTAN canonical resources
fetch_file "https://ctan.math.illinois.edu/macros/latex/contrib/revtex/aps/apsguide4-2.pdf" "$RES_DIR/apsguide4-2.pdf" "APS Author Guide for REVTeX 4.2 from CTAN mirror"
fetch_file "https://ctan.math.illinois.edu/macros/latex/contrib/revtex/sample/aps/apstemplate.tex" "$RES_DIR/apstemplate.tex" "APS template from CTAN mirror"

# H: REVTeX distribution zip (APS page link preferred, fallback CTAN zip)
ZIP_URL="$(extract_first_zip_url "$RES_DIR/revtex_home.html" "https://journals.aps.org" || true)"
ZIP_NOTES="REVTeX distribution archive"
if [[ -z "$ZIP_URL" ]]; then
  ZIP_URL="https://ctan.math.illinois.edu/macros/latex/contrib/revtex.zip"
  ZIP_NOTES="REVTeX distribution archive from CTAN fallback (APS direct zip link not found in snapshot)"
fi
fetch_file "$ZIP_URL" "$RES_DIR/revtex-tds.zip" "$ZIP_NOTES"

# Always write a human-readable status file for offline pack state.
{
  echo "# PRL Writer Offline Resources Status"
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
  echo "If any entry is [failed], rerun:"
  echo "\`bash AGENTS/skills/prl_writer/scripts/fetch_resources.sh\`"
} > "$STATUS_MD"

exit 0
