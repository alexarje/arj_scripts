#!/bin/bash
# Usage: video_normalize_audio.sh
# Loudness-normalize each video in the current directory -> *_norm.mp4

set -euo pipefail
shopt -s nullglob

progress_file=$(mktemp)
trap 'rm -f "$progress_file"' EXIT

draw_bar() {
    local pct=$1 width=40 bar="" j
    local filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do
        [[ $j -lt $filled ]] && bar+="#" || bar+=" "
    done
    printf "\r  [%s] %3d%%" "$bar" "$pct"
}

# Collect files first so we know the total
files=()
for i in *.mp4 *.MP4 *.mov *.MOV *.flv *.webm *.m4v; do
    [[ "$i" == *_norm.mp4 ]] && continue
    files+=("$i")
done

total=${#files[@]}
if [ "$total" -eq 0 ]; then
  echo "No video files found in current directory." >&2
  exit 1
fi

count=0
for i in "${files[@]}"; do
    name="${i%.*}"
    (( ++count ))
    printf "File %d/%d: %s\n" "$count" "$total" "$i"

    duration_us=$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "$i" 2>/dev/null \
      | awk '{printf "%d", $1 * 1000000}')

    > "$progress_file"
    ffmpeg -hide_banner -loglevel error -progress "$progress_file" -i "$i" \
      -c:v copy -max_muxing_queue_size 4096 -threads 4 \
      -af "loudnorm=I=-16:LRA=11:TP=-1.5,afade=d=5,afade=d=5" "${name}_norm.mp4" &
    ffmpeg_pid=$!

    while kill -0 "$ffmpeg_pid" 2>/dev/null; do
        out_time_us=$(grep "^out_time_us=" "$progress_file" 2>/dev/null | tail -1 | cut -d= -f2 || true)
        if [[ -n "${out_time_us:-}" && "${out_time_us:-0}" -gt 0 && "${duration_us:-0}" -gt 0 ]]; then
            pct=$(( out_time_us * 100 / duration_us ))
            [[ $pct -gt 100 ]] && pct=100
            draw_bar "$pct"
        fi
        sleep 0.5
    done
    wait "$ffmpeg_pid"
    draw_bar 100
    echo
done

echo "Normalized $count file(s)."
