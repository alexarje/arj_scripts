#!/bin/bash
# Usage: video_normalize_audio.sh
# Loudness-normalize each video in the current directory -> *_norm.mp4

set -euo pipefail
shopt -s nullglob
IFS=$'\n'
count=0
for i in *.mp4 *.MP4 *.mov *.MOV *.flv *.webm *.m4v; do
    name="${i%.*}"
    ffmpeg -hide_banner -loglevel error -i "$i" -c:v copy -max_muxing_queue_size 4096 -threads 4 \
      -af "loudnorm=I=-16:LRA=11:TP=-1.5,afade=d=5,afade=d=5" "${name}_norm.mp4"
    ((count++))
done

if [ "$count" -eq 0 ]; then
  echo "No video files found in current directory." >&2
  exit 1
fi

echo "Normalized $count file(s)."
