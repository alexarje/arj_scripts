#!/bin/bash
# Usage: folder_report.sh [directory]

FOLDER="${1:-.}"

if [ ! -d "$FOLDER" ]; then
  echo "Error: directory not found: $FOLDER" >&2
  exit 1
fi

echo "Number of files by type:"
echo "Audio: $(find "$FOLDER" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) | wc -l)"
echo "Video: $(find "$FOLDER" -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" \) | wc -l)"
echo "Documents: $(find "$FOLDER" -type f \( -iname "*.pdf" -o -iname "*.docx" -o -iname "*.xlsx" \) | wc -l)"
echo "Images: $(find "$FOLDER" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" \) | wc -l)"

echo "Total size by type:"
echo "Audio: $(find "$FOLDER" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) -exec du -ch {} + | grep total$)"
echo "Video: $(find "$FOLDER" -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" \) -exec du -ch {} + | grep total$)"
echo "Documents: $(find "$FOLDER" -type f \( -iname "*.pdf" -o -iname "*.docx" -o -iname "*.xlsx" \) -exec du -ch {} + | grep total$)"
echo "Images: $(find "$FOLDER" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" \) -exec du -ch {} + | grep total$)"

echo "File owners by type:"
echo "Audio:"
find "$FOLDER" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) -exec ls -l {} + | awk '{print $3}' | sort | uniq -c
echo "Video:"
find "$FOLDER" -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" \) -exec ls -l {} + | awk '{print $3}' | sort | uniq -c
echo "Documents:"
find "$FOLDER" -type f \( -iname "*.pdf" -o -iname "*.docx" -o -iname "*.xlsx" \) -exec ls -l {} + | awk '{print $3}' | sort | uniq -c
echo "Images:"
find "$FOLDER" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" \) -exec ls -l {} + | awk '{print $3}' | sort | uniq -c