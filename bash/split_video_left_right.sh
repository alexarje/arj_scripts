#!/usr/bin/env bash
set -euo pipefail

# Split a video into left and right halves.
#
# Usage:
#   scripts/split_video_left_right.sh -i /path/video.mp4
#   scripts/split_video_left_right.sh -i /path/video.mp4 -l left.mp4 -r right.mp4
#
# Options:
#   -i, --input FILE    Input video file (required)
#   -l, --left FILE     Output file for left half
#   -r, --right FILE    Output file for right half
#   -q, --crf N         H.264 CRF quality (default: 20)
#   -p, --preset NAME   x264 preset (default: medium)
#   -h, --help          Show help

print_help() {
  sed -n '2,18p' "$0"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

input=""
left_out=""
right_out=""
crf="20"
preset="medium"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      input="$2"
      shift 2
      ;;
    -l|--left)
      left_out="$2"
      shift 2
      ;;
    -r|--right)
      right_out="$2"
      shift 2
      ;;
    -q|--crf)
      crf="$2"
      shift 2
      ;;
    -p|--preset)
      preset="$2"
      shift 2
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

if [[ -z "$input" ]]; then
  echo "Error: --input is required." >&2
  print_help
  exit 1
fi

if [[ ! -f "$input" ]]; then
  echo "Error: input file not found: $input" >&2
  exit 1
fi

require_cmd ffmpeg
require_cmd ffprobe

if [[ -z "$left_out" ]]; then
  left_out="${input%.*}_left.mp4"
fi
if [[ -z "$right_out" ]]; then
  right_out="${input%.*}_right.mp4"
fi

mkdir -p "$(dirname "$left_out")"
mkdir -p "$(dirname "$right_out")"

# Split in one pass using scale2ref to ensure equal widths.
ffmpeg -hide_banner -loglevel warning -y \
  -i "$input" \
  -filter_complex "[0:v]split=2[v1][v2];[v1]crop=iw/2:ih:0:0,format=yuv420p[left];[v2]crop=iw/2:ih:iw/2:0,format=yuv420p[right]" \
  -map "[left]" -map 0:a? -c:v libx264 -crf "$crf" -preset "$preset" -c:a aac -b:a 160k "$left_out" \
  -map "[right]" -map 0:a? -c:v libx264 -crf "$crf" -preset "$preset" -c:a aac -b:a 160k "$right_out"

left_dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$left_out")"
right_dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$right_out")"

echo "Created left:  $left_out"
echo "Created right: $right_out"
echo "Left duration:  ${left_dur}s"
echo "Right duration: ${right_dur}s"
