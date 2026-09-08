#!/bin/bash
# tune-insta360-fov.sh — find the per-lens FOV that minimizes seam mismatch
# for an Insta360 dual-fisheye recording. Run once per camera/firmware; then
# pass the winning value to stitch360.sh with -f.
#
# Usage: tune-insta360-fov.sh input.insv [test-time-seconds ...]
# (For a lens-pair recording, pass the _00_ file; the _10_ mate is found.)
set -euo pipefail
[ $# -lt 1 ] && { grep '^#' "$0" | head -8; exit 1; }
F=$1; shift
TIMES=("${@:-120}"); [ ${#TIMES[@]} -eq 0 ] && TIMES=(120)

read -r vw vh < <(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height -of csv=p=0 "$F" | tr ',' ' ')
if [ "$vw" -eq "$vh" ]; then
  MATE="${F/_00_/_10_}"
  PRE=(-i "$F" -i "$MATE")
  GRAPH_PREFIX="[0:v][1:v]hstack,"
else
  PRE=(-i "$F")
  GRAPH_PREFIX=""
fi

best_fov=""; best_err=""
for fov in 186 188 190 192 193 194 195 196 198 200; do
  total=0; n=0
  for t in "${TIMES[@]}"; do
    err=$(ffmpeg -nostdin -v error -ss "$t" "${PRE[@]}" -filter_complex \
      "${GRAPH_PREFIX}v360=dfisheye:equirect:ih_fov=${fov}:iv_fov=${fov}:w=1920:h=960[v]" \
      -map "[v]" -frames:v 1 -pix_fmt gray -f rawvideo - 2>/dev/null | \
      python3 -c "
import sys, numpy as np
img = np.frombuffer(sys.stdin.buffer.read()[:1920*960], dtype=np.uint8).reshape(960,1920).astype(float)
e = 0
for sx in (480, 1440):
    e += np.abs(img[200:800, sx-3:sx-1].mean(1) - img[200:800, sx+1:sx+3].mean(1)).mean()
print(e/2)")
    total=$(python3 -c "print($total + $err)"); n=$((n+1))
  done
  mean=$(python3 -c "print(round($total/$n, 2))")
  echo "fov $fov : seam mismatch $mean"
  if [ -z "$best_err" ] || python3 -c "exit(0 if $mean < $best_err else 1)"; then
    best_err=$mean; best_fov=$fov
  fi
done
echo ""
echo "BEST: -f $best_fov (mismatch $best_err) — refine in 0.5 steps around it if needed"
