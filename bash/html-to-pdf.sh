#!/bin/bash
# filepath: convert_html_to_pdf.sh

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

# Set directory (default to current directory if not specified)
HTML_DIR="${1:-.}"
OUTPUT_PDF="combined_output.pdf"
TEMP_DIR=$(mktemp -d)

echo "Converting HTML files to individual PDFs..."

# Convert each HTML file to PDF
for html_file in "$HTML_DIR"/*.html; do
    if [ -f "$html_file" ]; then
        base_name=$(basename "$html_file" .html)
        pdf_file="$TEMP_DIR/${base_name}.pdf"
        echo "  Converting: $(basename "$html_file")"
        wkhtmltopdf "$html_file" "$pdf_file" 2>/dev/null
    fi
done

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