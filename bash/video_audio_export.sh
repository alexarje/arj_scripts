#!/bin/bash
# Usage: video_audio_export.sh
# Extract audio from each .mp4 in the current directory to .aac (stream copy).

set -euo pipefail
shopt -s nullglob

draw_bar() {
    local cur=$1 total=$2 width=40 bar="" j pct filled
    pct=$(( total > 0 ? cur * 100 / total : 100 ))
    filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do [[ $j -lt $filled ]] && bar+="#" || bar+=" "; done
    printf "\r  [%s] %3d%% (%d/%d)" "$bar" "$pct" "$cur" "$total"
}

files=()
for i in *.mp4 *.MP4; do files+=("$i"); done

total=${#files[@]}
if [ "$total" -eq 0 ]; then
  echo "No .mp4 files found in current directory." >&2
  exit 1
fi

count=0
for i in "${files[@]}"; do
  name="${i%.*}"
  ffmpeg -hide_banner -loglevel error -i "$i" -c copy "${name}.aac"
  (( ++count ))
  draw_bar "$count" "$total"
done
echo

echo "Extracted audio from $count file(s)."
