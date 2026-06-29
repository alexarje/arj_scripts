#!/bin/bash
# Usage: count_words_pdf.sh [directory]

set -euo pipefail

FOLDER="${1:-.}"

if [ ! -d "$FOLDER" ]; then
  echo "Error: directory not found: $FOLDER" >&2
  exit 1
fi

draw_bar() {
    local cur=$1 total=$2 width=40 bar="" j pct filled
    pct=$(( total > 0 ? cur * 100 / total : 100 ))
    filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do [[ $j -lt $filled ]] && bar+="#" || bar+=" "; done
    printf "\r  [%s] %3d%% (%d/%d)" "$bar" "$pct" "$cur" "$total"
}

shopt -s nullglob
pdfs=("$FOLDER"/*.pdf)
total=${#pdfs[@]}
if [ "$total" -eq 0 ]; then
  echo "No PDF files found in $FOLDER." >&2
  exit 1
fi

count=0
results=()
for pdf in "${pdfs[@]}"; do
  # Convert PDF to text, count words, then discard the text file.
  pdftotext "$pdf" "${pdf%.pdf}.txt"
  word_count=$(wc -w < "${pdf%.pdf}.txt")
  rm -f "${pdf%.pdf}.txt"

  results+=("File: $pdf - Words: $word_count")
  (( ++count ))
  draw_bar "$count" "$total"
done
echo

printf '%s\n' "${results[@]}"
