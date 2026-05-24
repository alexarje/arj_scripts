#!/usr/bin/env bash
set -euo pipefail

# Generate one or more rectilinear (defisheye) views from a fisheye video.
#
# Usage:
#   scripts/defisheye_views.sh -i /path/input.mp4
#   scripts/defisheye_views.sh -i /path/input.mp4 -o /path/outdir -w 1920 -h 1080
#   scripts/defisheye_views.sh -i /path/input.mp4 --preset medium
#
# Presets:
#   wide   : h_fov=125, v_fov=85
#   medium : h_fov=110, v_fov=70
#   tight  : h_fov=95,  v_fov=60
#
# Options:
#   -i, --input FILE      Input video file (required)
#   -o, --outdir DIR      Output directory (default: input directory)
#   -w, --width PX        Output width (default: 1280)
#   -h, --height PX       Output height (default: 720)
#       --ih-fov DEG      Input horizontal fisheye FOV (default: 180)
#       --iv-fov DEG      Input vertical fisheye FOV (default: 180)
#       --preset NAME     One of: wide, medium, tight, all (default: all)
#   -q, --crf N           H.264 CRF quality (default: 20)
#   -p, --preset-speed S  x264 preset speed (default: medium)
#       --overwrite       Overwrite outputs if they exist
#       --dry-run         Print commands without running
#       --help            Show help

print_help() {
  sed -n '2,40p' "$0"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

input=""
outdir=""
width="1280"
height="720"
ih_fov="180"
iv_fov="180"
view_preset="all"
crf="20"
enc_preset="medium"
overwrite="false"
dry_run="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      input="$2"
      shift 2
      ;;
    -o|--outdir)
      outdir="$2"
      shift 2
      ;;
    -w|--width)
      width="$2"
      shift 2
      ;;
    -h|--height)
      height="$2"
      shift 2
      ;;
    --ih-fov)
      ih_fov="$2"
      shift 2
      ;;
    --iv-fov)
      iv_fov="$2"
      shift 2
      ;;
    --preset)
      view_preset="$2"
      shift 2
      ;;
    -q|--crf)
      crf="$2"
      shift 2
      ;;
    -p|--preset-speed)
      enc_preset="$2"
      shift 2
      ;;
    --overwrite)
      overwrite="true"
      shift
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --help)
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

if [[ -z "$outdir" ]]; then
  outdir="$(dirname "$input")"
fi
mkdir -p "$outdir"

base_name="$(basename "$input")"
base_no_ext="${base_name%.*}"

build_and_run() {
  local name="$1"
  local h_fov="$2"
  local v_fov="$3"
  local output="$outdir/${base_no_ext}_straight_${name}.mp4"

  local overwrite_flag="-n"
  if [[ "$overwrite" == "true" ]]; then
    overwrite_flag="-y"
  fi

  local vf="v360=input=fisheye:output=rectilinear:ih_fov=${ih_fov}:iv_fov=${iv_fov}:h_fov=${h_fov}:v_fov=${v_fov}:w=${width}:h=${height},format=yuv420p"

  echo "Preset: ${name} (h_fov=${h_fov}, v_fov=${v_fov})"
  echo "Output: ${output}"

  if [[ "$dry_run" == "true" ]]; then
    echo "ffmpeg ${overwrite_flag} -i '$input' -vf '$vf' -c:v libx264 -crf $crf -preset $enc_preset -c:a aac -b:a 192k '$output'"
    return
  fi

  ffmpeg -hide_banner -loglevel warning ${overwrite_flag} \
    -i "$input" \
    -vf "$vf" \
    -c:v libx264 -crf "$crf" -preset "$enc_preset" \
    -c:a aac -b:a 192k \
    "$output"

  local duration
  duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$output")"
  local size
  size="$(du -h "$output" | awk '{print $1}')"
  echo "Done: ${output} | duration=${duration}s | size=${size}"
  echo
}

case "$view_preset" in
  wide)
    build_and_run "wide" "125" "85"
    ;;
  medium)
    build_and_run "medium" "110" "70"
    ;;
  tight)
    build_and_run "tight" "95" "60"
    ;;
  all)
    build_and_run "wide" "125" "85"
    build_and_run "medium" "110" "70"
    build_and_run "tight" "95" "60"
    ;;
  *)
    echo "Error: invalid --preset value: $view_preset (use wide|medium|tight|all)" >&2
    exit 1
    ;;
esac

echo "Finished."
