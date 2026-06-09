#!/bin/bash
# Usage: video_audio_export.sh
# Extract audio from each .mp4 in the current directory to .aac (stream copy).

set -euo pipefail
shopt -s nullglob

count=0
for i in *.mp4 *.MP4; do
  name="${i%.*}"
  ffmpeg -hide_banner -loglevel error -i "$i" -c copy "${name}.aac"
  ((count++))
done

if [ "$count" -eq 0 ]; then
  echo "No .mp4 files found in current directory." >&2
  exit 1
fi

echo "Extracted audio from $count file(s)."
