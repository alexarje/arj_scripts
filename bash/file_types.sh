#!/bin/bash

# Check if the directory is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <directory>"
  exit 1
fi

# Directory to search
DIR=$1

# Initialize counters
declare -A file_types
file_types=( ["audio"]=0 ["video"]=0 ["document"]=0 ["image"]=0 ["binary"]=0 ["other"]=0 )

# Function to categorize file types based on extensions
categorize_file() {
  case "$1" in
    *.wav|*.aiff|*.mp3|*.flac|*.ogg|*.m4a) file_types["audio"]=$((file_types["audio"] + 1)) ;;
    *.mp4|*.avi|*.mkv|*.mov|*.wmv|*.flv) file_types["video"]=$((file_types["video"] + 1)) ;;
    *.doc|*.docx|*.odt|*.txt|*.rtf|*.pdf) file_types["document"]=$((file_types["document"] + 1)) ;;
    *.jpg|*.jpeg|*.gif|*.png|*.tiff|*.bmp|*.svg) file_types["image"]=$((file_types["image"] + 1)) ;;
    *.exe|*.bin|*.iso|*.dll) file_types["binary"]=$((file_types["binary"] + 1)) ;;
    *) file_types["other"]=$((file_types["other"] + 1)) ;;
  esac
}

# Find all files and determine their types
echo "Searching for file types in $DIR..."

# Use find command to get file extensions
total_files=$(find "$DIR" -type f | wc -l)
current_file=0

find "$DIR" -type f | while read -r file; do
  echo "Processing file: $file"  # Debugging output
  categorize_file "$file"
  current_file=$((current_file + 1))
  echo -ne "Processing: $current_file/$total_files files\r"
done

# Display the results
echo -e "\nFile types and their counts:"
for type in "${!file_types[@]}"; do
  echo "$type: ${file_types[$type]}"
done