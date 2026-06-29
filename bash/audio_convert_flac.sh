#!/bin/bash
# Usage: audio_convert_flac.sh [directory] [output.flac]

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

input_dir="${1:-.}"
output_file="${2:-output.flac}"
file_list="$(mktemp)"

if [ ! -d "$input_dir" ]; then
  echo "Error: directory not found: $input_dir" >&2
  exit 1
fi

trap 'rm -f "$file_list"' EXIT

total_dur=0
for wav_file in "$input_dir"/*.{WAV,wav}; do
  echo "file '$wav_file'" >> "$file_list"
  d=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$wav_file" 2>/dev/null || echo 0)
  total_dur=$(awk "BEGIN{print $total_dur + ${d:-0}}")
done

if [ ! -s "$file_list" ]; then
  echo "Error: no WAV files found in $input_dir" >&2
  exit 1
fi

ffmpeg_bar "$total_dur" -f concat -safe 0 -i "$file_list" -ar 48000 -sample_fmt s16 -c:a flac "$output_file"
echo "Merged FLAC file created: $output_file"
