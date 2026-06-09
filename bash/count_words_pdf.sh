#!/bin/bash
# Usage: count_words_pdf.sh [directory]

FOLDER="${1:-.}"

if [ ! -d "$FOLDER" ]; then
  echo "Error: directory not found: $FOLDER" >&2
  exit 1
fi

shopt -s nullglob
for pdf in "$FOLDER"/*.pdf; 
do
  # Convert PDF to text
  pdftotext "$pdf" "${pdf%.pdf}.txt"
  
  # Count words in the text file
  word_count=$(wc -w < "${pdf%.pdf}.txt")
  
  # Print the word count
  echo "File: $pdf - Words: $word_count"
  
  # Remove the text file
  rm "${pdf%.pdf}.txt"
done
