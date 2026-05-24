#!/usr/bin/env bash

# Enable case-insensitive globbing and ignore non-matching patterns.
shopt -s nocaseglob nullglob

output_file="output.mp4"
force_overwrite=0
for arg in "$@"; do
  case "$arg" in
    --force|-f)
      force_overwrite=1
      ;;
    *)
      output_file="$arg"
      ;;
  esac
done

if [[ -e "$output_file" ]]; then
  if (( force_overwrite == 1 )); then
    rm -f -- "$output_file"
  else
    echo "Refusing to overwrite existing file: $output_file" >&2
    echo "Run with --force to overwrite." >&2
    exit 1
  fi
fi

list_file="$(mktemp "${TMPDIR:-/tmp}/ffmpeg-concat.XXXXXX.txt")"
trap 'rm -f "$list_file"' EXIT

added=0
for ext in mts mp4 mkv avi flv wmv webm; do
  for file in *."$ext"; do
    abs_file="$PWD/$file"
    escaped_file=${abs_file//\'/\'\\\'\'}
    printf "file '%s'\n" "$escaped_file" >> "$list_file"
    ((added++))
  done
done

if (( added == 0 )); then
  echo "No matching video files found in current directory." >&2
  exit 1
fi

# Concatenate files.
# MP4 cannot store some source audio codecs (for example pcm_bluray), so
# keep video copy and transcode audio to AAC when output is MP4.
if [[ "${output_file##*.}" =~ ^([mM][pP]4)$ ]]; then
  ffmpeg -f concat -safe 0 -i "$list_file" -c:v copy -c:a aac -b:a 192k -movflags +faststart "$output_file"
else
  ffmpeg -f concat -safe 0 -i "$list_file" -c copy "$output_file"
fi

# Disable shell options we enabled.
shopt -u nocaseglob nullglob
