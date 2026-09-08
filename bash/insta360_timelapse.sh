#!/bin/bash
# insta360_timelapse.sh — timelapse from Insta360 .insp dual-fisheye photos,
# with a linearized (rectilinear) crop of one fisheye via ffmpeg's v360 filter.
#
# Each .insp is a JPEG with the two fisheyes side by side (left | right),
# plus an embedded thumbnail — so files are decoded one by one (-frames:v 1)
# instead of piped as one stream.
#
# Frames are ordered by EXIF DateTimeOriginal, NOT by filename: the camera's
# file counter wraps 999 -> 001, so alphabetical order scrambles any session
# that crosses the wrap. Requires exiftool.
#
# Usage:
#   ./insta360_timelapse.sh -i puslespill -o puzzle.mp4 [options]
#
# Options (defaults match the puzzle timelapse, July 2026):
#   -i DIR     input directory with .insp files (required)
#   -o FILE    output video (default: timelapse.mp4)
#   -l         use LEFT fisheye instead of right
#   -y DEG     yaw   — pan   left(-)/right(+)   (default: -8)
#   -p DEG     pitch — tilt  down(-)/up(+)      (default: -12)
#   -f DEG     horizontal field of view          (default: 75)
#   -r FPS     output frame rate                 (default: 30)
#   -s WxH     output size, 16:9                 (default: 1920x1080)
#   -g         encode with NVIDIA NVENC (h264_nvenc) instead of libx264
#   -t         test mode: render only the middle frame of the sequence
#              to preview.jpg next to the output, then exit
#
# GPU note (benchmarked on RTX 3500 Ada + Iris Xe, July 2026): frame
# extraction stays on the CPU on purpose. NVDEC rejects these JPEGs
# (4:2:2 chroma; it only does 4:2:0), Intel VAAPI decode measured slower
# than software once format conversions are counted, and the v360
# reprojection filter is CPU-only in ffmpeg. Only the final encode can
# use the GPU (-g); it saves a minute or two on the encode stage.
#
# Tip for aiming: run with -t, look at preview.jpg, adjust -y/-p/-f, repeat.
#
# Note: intermediate frames live in a temp dir that is removed on exit, so an
# interrupted run starts over. Expect roughly 1s/frame of extraction on a
# 20-core CPU (~25 min per 1400 shots).

set -euo pipefail

SRC="" OUT="timelapse.mp4" SIDE=right
YAW=-8 PITCH=-12 HFOV=75 FPS=30 SIZE=1920x1080 TEST=0 GPU=0

while getopts "i:o:ly:p:f:r:s:gt" opt; do
  case $opt in
    i) SRC=$OPTARG ;;
    o) OUT=$OPTARG ;;
    l) SIDE=left ;;
    y) YAW=$OPTARG ;;
    p) PITCH=$OPTARG ;;
    f) HFOV=$OPTARG ;;
    r) FPS=$OPTARG ;;
    s) SIZE=$OPTARG ;;
    g) GPU=1 ;;
    t) TEST=1 ;;
    *) exit 1 ;;
  esac
done
[ -n "$SRC" ] || { echo "error: -i input dir required" >&2; exit 1; }
command -v exiftool >/dev/null || { echo "error: exiftool required" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Order by capture time — filename order breaks when the counter wraps 999->001.
LIST="$WORK/ordered.txt"
exiftool -q -fast2 -d '%Y%m%d%H%M%S' -p '$DateTimeOriginal $FileName' \
  "$SRC"/*.insp | sort -k1,1 -k2,2 | awk '{print $2}' > "$LIST"

# Sensor geometry: each fisheye circle is half the frame width, ~195 deg FOV.
W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 \
      "$(ls "$SRC"/*.insp | head -1)")
HALF=$((W / 2))
XOFF=$([ "$SIDE" = right ] && echo "$HALF" || echo 0)

# v_fov consistent with 16:9 rectilinear output: tan(v/2) = tan(h/2) * 9/16
VFOV=$(awk -v h="$HFOV" 'BEGIN{pi=atan2(0,-1);
  printf "%.1f", 2*atan2(sin(h/2*pi/180)/cos(h/2*pi/180)*9/16, 1)*180/pi}')

VF="crop=$HALF:$HALF:$XOFF:0,\
v360=input=fisheye:output=flat:ih_fov=195:iv_fov=195:\
yaw=$YAW:pitch=$PITCH:h_fov=$HFOV:v_fov=$VFOV,\
scale=${SIZE/x/:}"

if [ "$TEST" = 1 ]; then
  MID=$(awk '{a[NR]=$0} END{print a[int(NR/2)]}' "$LIST")
  PREVIEW="$(dirname "$OUT")/preview.jpg"
  ffmpeg -nostdin -loglevel error -y -i "$SRC/$MID" -frames:v 1 -vf "$VF" \
         -q:v 2 -update 1 "$PREVIEW"
  echo "wrote $PREVIEW (from $MID) — adjust -y/-p/-f and rerun"
  exit 0
fi

FRAMES="$WORK/frames"
mkdir -p "$FRAMES"
N=$(wc -l < "$LIST")
JOBS=$(( $(nproc) - 2 )); [ "$JOBS" -ge 1 ] || JOBS=1

echo "stage 1/2: extracting $N frames ($JOBS parallel jobs)..."
nl -ba -nrz -w5 "$LIST" | while read -r idx name; do
  printf '%s\0%s\0' "$idx" "$name"
done | SRC="$SRC" FRAMES="$FRAMES" VF="$VF" xargs -0 -n 2 -P "$JOBS" sh -c '
  ffmpeg -nostdin -loglevel error -y -i "$SRC/$1" -frames:v 1 -vf "$VF" \
         -q:v 2 -update 1 "$FRAMES/f_$0.jpg"
'

GOT=$(ls "$FRAMES" | wc -l)
[ "$GOT" = "$N" ] || { echo "error: only $GOT/$N frames extracted" >&2; exit 1; }

echo "stage 2/2: encoding $OUT..."
if [ "$GPU" = 1 ]; then
  ENC=(-c:v h264_nvenc -preset p6 -rc vbr -cq 21 -b:v 0)
else
  ENC=(-c:v libx264 -preset medium -crf 18)
fi
ffmpeg -nostdin -loglevel error -y -framerate "$FPS" -i "$FRAMES/f_%05d.jpg" \
       -vf "deflicker=size=5" "${ENC[@]}" \
       -pix_fmt yuv420p -movflags +faststart "$OUT"

echo "done: $OUT ($N frames @ ${FPS}fps = $(awk -v n="$N" -v r="$FPS" \
  'BEGIN{printf "%.1f", n/r}')s)"
