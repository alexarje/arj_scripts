#!/usr/bin/env bash
set -euo pipefail

# Create a timelapse video from .insp files in a folder.
# Dependencies: ffmpeg, ffprobe
#
# Usage:
#   scripts/insp_timelapse.sh -i /path/to/folder [-o output.mp4] [options]
#
# Options:
#   -i, --input DIR           Input folder containing .insp files (required)
#   -o, --output FILE         Output MP4 path (default: <input>_timelapse.mp4)
#   -d, --duration SEC        Seconds per frame/file (default: 0.08)
#   -w, --width PX            Output width in pixels (default: 1920)
#   -f, --fps FPS             Output frames per second (default: 30)
#   -r, --recursive           Include .insp files in subfolders
#   -h, --help                Show this help

print_help() {
  sed -n '2,20p' "$0"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

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
        if [[ "${out_us:-}" =~ ^[0-9]+$ && "${total_us:-}" =~ ^[0-9]+$ && $total_us -gt 0 ]]; then
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

input_dir=""
output_file=""
frame_duration="0.08"
out_width="1920"
out_fps="30"
recursive="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      input_dir="$2"
      shift 2
      ;;
    -o|--output)
      output_file="$2"
      shift 2
      ;;
    -d|--duration)
      frame_duration="$2"
      shift 2
      ;;
    -w|--width)
      out_width="$2"
      shift 2
      ;;
    -f|--fps)
      out_fps="$2"
      shift 2
      ;;
    -r|--recursive)
      recursive="true"
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      print_help
      exit 1
      ;;
  esac
done

if [[ -z "$input_dir" ]]; then
  echo "Error: --input is required." >&2
  print_help
  exit 1
fi

if [[ ! -d "$input_dir" ]]; then
  echo "Error: input folder does not exist: $input_dir" >&2
  exit 1
fi

require_cmd ffmpeg
require_cmd ffprobe
require_cmd find
require_cmd sort

if [[ -z "$output_file" ]]; then
  output_file="${input_dir%/}_timelapse.mp4"
fi

# Gather and sort source files.
if [[ "$recursive" == "true" ]]; then
  mapfile -t files < <(find "$input_dir" -type f -iname '*.insp' | sort)
else
  mapfile -t files < <(find "$input_dir" -maxdepth 1 -type f -iname '*.insp' | sort)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "Error: no .insp files found in $input_dir" >&2
  exit 1
fi

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

seq_dir="$workdir/seq"
mkdir -p "$seq_dir"

# ffmpeg's image demuxers are extension-sensitive; symlink .insp files as .jpg.
index=1
for f in "${files[@]}"; do
  printf -v num '%06d' "$index"
  ln -s "$f" "$seq_dir/frame_${num}.jpg"
  index=$((index + 1))
done

cat > "$workdir/list.ffconcat" <<EOF
ffconcat version 1.0
EOF

for f in "$seq_dir"/*.jpg; do
  printf "file '%s'\n" "$f" >> "$workdir/list.ffconcat"
  printf "duration %s\n" "$frame_duration" >> "$workdir/list.ffconcat"
done
# Repeat last frame once for concat duration behavior.
last_file="$(ls "$seq_dir"/*.jpg | tail -n 1)"
printf "file '%s'\n" "$last_file" >> "$workdir/list.ffconcat"

mkdir -p "$(dirname "$output_file")"

# Output runs one frame_duration per source frame.
total_dur=$(awk "BEGIN{printf \"%.3f\", ${#files[@]} * $frame_duration}")

ffmpeg_bar "$total_dur" -y \
  -f concat -safe 0 -i "$workdir/list.ffconcat" \
  -vf "scale=${out_width}:-2,format=yuv420p" \
  -r "$out_fps" \
  -c:v libx264 -crf 20 -preset medium \
  "$output_file"

duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$output_file")"
size_h="$(du -h "$output_file" | awk '{print $1}')"

echo "Created: $output_file"
echo "Frames: ${#files[@]}"
echo "Duration: ${duration}s"
echo "Size: $size_h"
