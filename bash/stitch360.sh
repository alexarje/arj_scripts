#!/bin/bash
# stitch360.sh — flatten 360 camera recordings to standardized equirectangular MP4.
#
# Supports:
#   GoPro Max .360          — dual-track EAC; strips the 32px overlap columns
#                             between cube faces before reprojection
#   Insta360 .insv (single) — dual-fisheye side-by-side in one file (e.g. 3840x1920)
#   Insta360 .insv (pair)   — one lens per file (_00_/_10_, e.g. 2880x2880 each);
#                             pass only the _00_ file, the _10_ mate is found
#
# Multiple input files are treated as chapters of ONE recording and joined
# into a single output. Camera type is auto-detected per file.
#
# Usage:
#   stitch360.sh [options] -o output.mp4 input1 [input2 ...]
#
# Options:
#   -o FILE     output file (required)
#   -f FOV      per-lens field of view for Insta360, degrees (default 194.5;
#               tune per camera with tune-insta360-fov.sh)
#   -r          camera was mounted upside down: add 180-degree roll
#   -s WxH      output size (default 1920x960; use 3840x1920 for full quality)
#   -p FPS      output frame rate (default 25)
#   -q CRF      x264 quality, lower = better (default 22)
#   -n          no audio
#
# Examples:
#   stitch360.sh -r -o session_equirect.mp4 GS01*.360 GS02*.360
#   stitch360.sh -o standstill.mp4 VID_20251010_114307_00_001.insv
#   stitch360.sh -r -f 194.5 -o session1.mp4 VID_*_00_*.insv
set -euo pipefail

FOV=194.5; ROLL=""; SIZE="1920x960"; FPS=25; CRF=22; OUT=""; AUDIO=1
while getopts "o:f:rs:p:q:n" opt; do
  case $opt in
    o) OUT=$OPTARG ;;
    f) FOV=$OPTARG ;;
    r) ROLL=":roll=180" ;;
    s) SIZE=$OPTARG ;;
    p) FPS=$OPTARG ;;
    q) CRF=$OPTARG ;;
    n) AUDIO=0 ;;
    *) exit 1 ;;
  esac
done
shift $((OPTIND - 1))
[ -z "$OUT" ] && { grep '^#' "$0" | head -30; echo "ERROR: -o output required"; exit 1; }
[ $# -lt 1 ] && { echo "ERROR: no input files"; exit 1; }
Wo=${SIZE%x*}; Ho=${SIZE#*x}
ENC=(-c:v libx264 -preset veryfast -crf "$CRF" -pix_fmt yuv420p -movflags +faststart)
[ $AUDIO -eq 1 ] && ENC+=(-c:a aac -b:a 128k) || ENC+=(-an)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

segs=(); i=0
for f in "$@"; do
  i=$((i + 1)); seg="$TMP/seg_$(printf %03d $i).mp4"
  case "${f,,}" in
    *.360)
      # GoPro Max: 2 HEVC tracks, 3 EAC faces each with 32px overlap strips
      GRAPH="[0:v:0]crop=1344:1344:0:0[t0];[0:v:0]crop=1344:1344:1376:0[t1];[0:v:0]crop=1344:1344:2752:0[t2];"
      GRAPH+="[0:v:1]crop=1344:1344:0:0[b0];[0:v:1]crop=1344:1344:1376:0[b1];[0:v:1]crop=1344:1344:2752:0[b2];"
      GRAPH+="[t0][t1][t2]hstack=3[top];[b0][b1][b2]hstack=3[bot];[top][bot]vstack[eac];"
      GRAPH+="[eac]v360=eac:equirect${ROLL}:w=${Wo}:h=${Ho},fps=${FPS}[v]"
      MAPA=(); [ $AUDIO -eq 1 ] && MAPA=(-map 0:a:0)
      echo "[$i] GoPro Max EAC: $(basename "$f")"
      ffmpeg -nostdin -y -v error -i "$f" -filter_complex "$GRAPH" \
        -map "[v]" "${MAPA[@]}" "${ENC[@]}" "$seg"
      ;;
    *.insv|*.mp4)
      read -r vw vh < <(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height -of csv=p=0 "$f" | tr ',' ' ')
      if [ "$vw" -eq "$vh" ]; then
        # square = one lens per file; find the _10_ mate of a _00_ file
        mate="${f/_00_/_10_}"
        [ "$mate" = "$f" ] || [ ! -f "$mate" ] && \
          { echo "ERROR: $f is single-lens but mate ($mate) not found"; exit 1; }
        echo "[$i] Insta360 lens pair: $(basename "$f") + $(basename "$mate")"
        MAPA=(); [ $AUDIO -eq 1 ] && MAPA=(-map 0:a:0)
        ffmpeg -nostdin -y -v error -i "$f" -i "$mate" -filter_complex \
          "[0:v][1:v]hstack,v360=dfisheye:equirect:ih_fov=${FOV}:iv_fov=${FOV}${ROLL}:w=${Wo}:h=${Ho},fps=${FPS}[v]" \
          -map "[v]" "${MAPA[@]}" "${ENC[@]}" "$seg"
      else
        # 2:1-ish = dual fisheye in one file
        echo "[$i] Insta360 dual-fisheye: $(basename "$f")"
        MAPA=(); [ $AUDIO -eq 1 ] && MAPA=(-map 0:a:0)
        ffmpeg -nostdin -y -v error -i "$f" -vf \
          "v360=dfisheye:equirect:ih_fov=${FOV}:iv_fov=${FOV}${ROLL}:w=${Wo}:h=${Ho},fps=${FPS}" \
          -map 0:v:0 "${MAPA[@]}" "${ENC[@]}" "$seg"
      fi
      ;;
    *) echo "ERROR: unknown input type: $f"; exit 1 ;;
  esac
  segs+=("$seg")
done

if [ ${#segs[@]} -eq 1 ]; then
  mv "${segs[0]}" "$OUT"
else
  : > "$TMP/list.txt"
  for s in "${segs[@]}"; do echo "file '$s'" >> "$TMP/list.txt"; done
  ffmpeg -nostdin -y -v error -f concat -safe 0 -i "$TMP/list.txt" -c copy "$OUT"
fi
echo "OK: $OUT ($(du -m "$OUT" | cut -f1) MB)"
