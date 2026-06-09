#!/bin/bash
# Usage: video_resize_hd.sh
# Resize each .mp4 in the current directory to 1080p/25fps (NVENC, requires CUDA).

set -euo pipefail
shopt -s nullglob

count=0
for i in *.mp4 *.MP4; do
  name="${i%.*}"
  ffmpeg -hide_banner -loglevel error -hwaccel cuda -i "$i" \
    -vf scale=1920:1080,fps=25 -c:v h264_nvenc -preset fast -b:v 5M -c:a copy "${name}_hd.mp4"
  ((count++))
done

if [ "$count" -eq 0 ]; then
  echo "No .mp4 files found in current directory." >&2
  exit 1
fi

echo "Resized $count file(s)."
