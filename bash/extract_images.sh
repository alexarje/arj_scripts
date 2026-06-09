#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_pdf> <output_directory>"
    exit 1
fi

input_pdf=$1
output_dir=$2

if [ ! -f "$input_pdf" ]; then
  echo "Error: PDF not found: $input_pdf" >&2
  exit 1
fi

# Create the output directory if it doesn't exist
mkdir -p "$output_dir"

# Extract images from the PDF file
pdfimages -all "$input_pdf" "$output_dir/image"

echo "Images extracted to $output_dir"