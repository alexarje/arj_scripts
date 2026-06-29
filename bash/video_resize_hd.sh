#!/bin/bash
# Usage: video_resize_hd.sh
# Resize each .mp4 in the current directory to 1080p/25fps (NVENC, requires CUDA).

set -euo pipefail
shopt -s nullglob

draw_bar() {
    local pct=$1 width=40 bar="" j filled
    filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do [[ $j -lt $filled ]] && bar+="#" || bar+=" "; done
    printf "\r  [%s] %3d%%" "$bar" "$pct"
}

# ffmpeg_bar <duration_seconds> <ffmpeg args...>
# Run ffmpeg quietly with a live progress bar scaled to the given duration.
ffmpeg_bar() {
    local dur="${1:-0}"; shift
    local pf total_us out_us pct pid rc=0
    pf=$(mktemp)
    total_us=$(awk "BEGIN{printf \"%d\", ($dur) * 1000000}")
    ffmpeg -hide_banner -loglevel error -progress "$pf" "$@" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        out_us=$(grep "^out_time_us=" "$pf" 2>/dev/null | tail -1 | cut -d= -f2 || true)
        if [[ -n "${out_us:-}" && "${out_us:-0}" -gt 0 && "${total_us:-0}" -gt 0 ]]; then
            pct=$(( out_us * 100 / total_us ))
            [[ $pct -gt 100 ]] && pct=100
            draw_bar "$pct"
        fi
        sleep 0.5
    done
    wait "$pid" || rc=$?
    rm -f "$pf"
    if [[ $rc -eq 0 ]]; then draw_bar 100; fi
    echo
    return $rc
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
  (( ++count ))
  printf "File %d/%d: %s\n" "$count" "$total" "$i"

  dur=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$i" 2>/dev/null || echo 0)

  ffmpeg_bar "$dur" -hwaccel cuda -i "$i" \
    -vf scale=1920:1080,fps=25 -c:v h264_nvenc -preset fast -b:v 5M -c:a copy "${name}_hd.mp4"
done

echo "Resized $count file(s)."
