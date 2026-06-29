#!/bin/bash
# Usage: html-to-pdf.sh [html_directory]

# Check if wkhtmltopdf is installed
if ! command -v wkhtmltopdf &> /dev/null; then
    echo "Error: wkhtmltopdf is not installed"
    echo "Install with: sudo apt-get install wkhtmltopdf"
    exit 1
fi

# Check if pdfunite is installed
if ! command -v pdfunite &> /dev/null; then
    echo "Error: pdfunite is not installed"
    echo "Install with: sudo apt-get install poppler-utils"
    exit 1
fi

HTML_DIR="${1:-.}"

if [ ! -d "$HTML_DIR" ]; then
  echo "Error: directory not found: $HTML_DIR" >&2
  exit 1
fi

draw_bar() {
    local cur=$1 total=$2 width=40 bar="" j pct filled
    pct=$(( total > 0 ? cur * 100 / total : 100 ))
    filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do [[ $j -lt $filled ]] && bar+="#" || bar+=" "; done
    printf "\r  [%s] %3d%% (%d/%d)" "$bar" "$pct" "$cur" "$total"
}

OUTPUT_PDF="combined_output.pdf"
TEMP_DIR=$(mktemp -d)

shopt -s nullglob
html_files=("$HTML_DIR"/*.html)
total=${#html_files[@]}
if [ "$total" -eq 0 ]; then
    echo "Error: No HTML files found in $HTML_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Converting $total HTML file(s) to individual PDFs..."

# Convert each HTML file to PDF
count=0
for html_file in "${html_files[@]}"; do
    [ -f "$html_file" ] || continue
    base_name=$(basename "$html_file" .html)
    pdf_file="$TEMP_DIR/${base_name}.pdf"
    wkhtmltopdf "$html_file" "$pdf_file" 2>/dev/null
    (( ++count ))
    draw_bar "$count" "$total"
done
echo

# Check if any PDFs were created
pdf_count=$(ls -1 "$TEMP_DIR"/*.pdf 2>/dev/null | wc -l)
if [ "$pdf_count" -eq 0 ]; then
    echo "Error: No HTML files found or conversion failed"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Combining PDFs into one file..."

# Combine all PDFs into one
pdfunite "$TEMP_DIR"/*.pdf "$OUTPUT_PDF"

# Cleanup
rm -rf "$TEMP_DIR"

echo "✓ Done! Combined PDF saved as: $OUTPUT_PDF"