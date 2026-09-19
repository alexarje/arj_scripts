#!/bin/bash
# Usage: video_normalize_audio.sh [-p] [-t TARGET]
# Level and loudness-normalize the audio of each video in the current directory -> *_norm.mp4
#   -p          plain: loudness normalisation only, no levelling
#   -t TARGET   integrated loudness in LUFS (default -16, the web figure; broadcast delivery is -23)
#
# The video stream is copied, so only the audio is touched and the pass is quick.
#
# Why two passes and a leveller. A recording of a room where several people speak into one
# microphone arrives with the voices at different levels, and with isolated bangs far above any of
# them. A single loudnorm pass handles neither well. It is asked for a target it often cannot reach
# with a plain gain, because the gain that would reach it puts the peaks above the ceiling, and it
# then falls back to a dynamic mode of its own without saying so. So:
#
#   1. a leveller whose gain is smoothed over about 6 s, which evens one speaker against the next
#      rather than one syllable against the next;
#   2. a true-peak limiter, which takes the isolated bangs that would otherwise eat the headroom;
#   3. a measuring pass over the levelled signal;
#   4. one linear gain to the target, which is now reachable, so the loudness step does not act as
#      a second compressor.
#
# Measured on a PhD defence where four voices spanned 10.9 LU: two voices 4.3 LU apart in the source
# came to 2.3 LU with loudness normalisation alone and 1.4 LU with the levelling in front of it.

set -euo pipefail
shopt -s nullglob

TARGET_I=-16
TARGET_TP=-1.5
TARGET_LRA=11
PLAIN=0

while getopts ":pt:" opt; do
    case "$opt" in
        p) PLAIN=1 ;;
        t) TARGET_I=$OPTARG ;;
        *) echo "Usage: $(basename "$0") [-p] [-t TARGET]" >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

# highpass: rumble and handling noise below the voice. dynaudnorm: gain smoothed over 31 frames of
# 200 ms, peak 0.9, up to 12x, towards a target RMS. alimiter: 0.84 is about -1.5 dBFS.
LEVEL="highpass=f=70,dynaudnorm=f=200:g=31:p=0.9:m=12:r=0.9,alimiter=limit=0.84:level=false"
[[ $PLAIN -eq 1 ]] && LEVEL=""

progress_file=$(mktemp)
measure_file=$(mktemp)
trap 'rm -f "$progress_file" "$measure_file"' EXIT

draw_bar() {
    local pct=$1 width=40 bar="" j filled
    filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do [[ $j -lt $filled ]] && bar+="#" || bar+=" "; done
    printf "\r  [%s] %3d%%" "$bar" "$pct"
}

field() { sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$measure_file"; }

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
    out="${name}_norm.mp4"
    (( ++count ))
    printf "File %d/%d: %s\n" "$count" "$total" "$i"
    if [[ -e "$out" ]]; then echo "  $out already on disk, skipped"; continue; fi

    duration=$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "$i" 2>/dev/null | awk '{printf "%d", $1}')

    # Pass 1: what the levelled signal measures.
    ffmpeg -hide_banner -nostats -i "$i" -vn \
      -af "${LEVEL:+$LEVEL,}loudnorm=I=$TARGET_I:TP=$TARGET_TP:LRA=$TARGET_LRA:print_format=json" \
      -f null - 2>&1 | sed -n '/^{/,/^}/p' > "$measure_file"
    mi=$(field input_i); mtp=$(field input_tp); mlra=$(field input_lra)
    mth=$(field input_thresh); moff=$(field target_offset)
    if [[ -z "$mi" ]]; then echo "  could not measure $i" >&2; exit 1; fi
    printf "  measured %s LUFS, range %s LU\n" "$mi" "$mlra"

    # Pass 2: the cut, with a fade in at the head and a fade out at the tail.
    fade="afade=t=in:st=0:d=5"
    [[ -n "${duration:-}" && "${duration:-0}" -gt 10 ]] && fade="$fade,afade=t=out:st=$((duration - 5)):d=5"

    > "$progress_file"
    ffmpeg -hide_banner -loglevel error -y -progress "$progress_file" -i "$i" \
      -c:v copy -max_muxing_queue_size 4096 -threads 4 \
      -af "${LEVEL:+$LEVEL,}loudnorm=I=$TARGET_I:TP=$TARGET_TP:LRA=$TARGET_LRA:measured_I=$mi:measured_TP=$mtp:measured_LRA=$mlra:measured_thresh=$mth:offset=$moff:linear=true,$fade" \
      -c:a aac -b:a 192k "$out" &
    ffmpeg_pid=$!

    while kill -0 "$ffmpeg_pid" 2>/dev/null; do
        out_time_us=$(grep "^out_time_us=" "$progress_file" 2>/dev/null | tail -1 | cut -d= -f2 || true)
        if [[ -n "${out_time_us:-}" && "${out_time_us:-0}" -gt 0 && "${duration:-0}" -gt 0 ]]; then
            pct=$(( out_time_us / 1000000 * 100 / duration ))
            [[ $pct -gt 100 ]] && pct=100
            draw_bar "$pct"
        fi
        sleep 0.5
    done
    wait "$ffmpeg_pid"
    draw_bar 100
    echo
    printf "  %s\n" "$(ffmpeg -hide_banner -nostats -i "$out" -vn -af ebur128=framelog=quiet -f null - 2>&1 \
      | grep -A3 'Integrated loudness' | grep 'I:' | tr -s ' ')"
done

echo "Normalized $count file(s)."
