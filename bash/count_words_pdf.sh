#!/bin/bash

# Check if the folder is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <folder>"
  exit 1
fi

# Check if the folder exists
if [ ! -d "$1" ]; then
  echo "Folder not found!"
  exit 1
fi

# Loop through all PDF files in the folder
for pdf in "$1"/*.pdf; 
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
