#!/bin/bash
# Usage: file_types.sh [directory]

DIR="${1:-.}"

if [ ! -d "$DIR" ]; then
  echo "Error: directory not found: $DIR" >&2
  exit 1
fi

declare -A file_types=(
  [audio]=0
  [video]=0
  [document]=0
  [image]=0
  [binary]=0
  [other]=0
)

categorize_file() {
  local base
  base=$(basename "$1")
  case "$base" in
    *.wav|*.aiff|*.mp3|*.flac|*.ogg|*.m4a) file_types[audio]=$((file_types[audio] + 1)) ;;
    *.mp4|*.avi|*.mkv|*.mov|*.wmv|*.flv) file_types[video]=$((file_types[video] + 1)) ;;
    *.doc|*.docx|*.odt|*.txt|*.rtf|*.pdf) file_types[document]=$((file_types[document] + 1)) ;;
    *.jpg|*.jpeg|*.gif|*.png|*.tiff|*.bmp|*.svg) file_types[image]=$((file_types[image] + 1)) ;;
    *.exe|*.bin|*.iso|*.dll) file_types[binary]=$((file_types[binary] + 1)) ;;
    *) file_types[other]=$((file_types[other] + 1)) ;;
  esac
}

echo "Searching for file types in $DIR..."

while IFS= read -r -d '' file; do
  categorize_file "$file"
done < <(find "$DIR" -type f -print0)

echo "File types and their counts:"
for type in audio video document image binary other; do
  echo "$type: ${file_types[$type]}"
done
