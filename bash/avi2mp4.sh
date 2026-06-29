#!/usr/bin/env bash
# Recursively convert every .avi file in a folder to .mp4 using GPU acceleration.
# Usage: avi2mp4.sh [folder]   (defaults to current directory)
# Output is written next to each source file as <name>.mp4; sources are left untouched.

set -euo pipefail

root="${1:-.}"
[[ -d $root ]] || { echo "Not a directory: $root" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }

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

# Pick a GPU H.264 encoder, mirroring video_merge_files_gpu.sh.
vflags=()
hwaccel=()
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_nvenc\>'; then
  hwaccel=(-hwaccel cuda)
  vflags=(-c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 19 -b:v 0 -spatial_aq 1 -temporal_aq 1)
  echo "Using NVIDIA NVENC"
elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_qsv\>'; then
  hwaccel=(-hwaccel qsv)
  vflags=(-c:v h264_qsv -preset veryslow -global_quality 19 -look_ahead 1)
  echo "Using Intel QuickSync"
elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_vaapi\>'; then
  vflags=(-vaapi_device /dev/dri/renderD128 -vf format=nv12,hwupload -c:v h264_vaapi -qp 19)
  echo "Using VAAPI"
elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_amf\>'; then
  vflags=(-c:v h264_amf -quality quality -rc cqp -qp_i 19 -qp_p 19 -qp_b 19)
  echo "Using AMD AMF"
elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_videotoolbox\>'; then
  hwaccel=(-hwaccel videotoolbox)
  vflags=(-c:v h264_videotoolbox -q:v 65)
  echo "Using VideoToolbox"
else
  vflags=(-c:v libx264 -preset medium -crf 18)
  echo "Warning: No GPU encoder found, falling back to CPU (libx264)"
fi

# Collect .avi files recursively (case-insensitive), NUL-delimited for safe names.
mapfile -d '' -t files < <(find "$root" -type f -iname '*.avi' -print0)

total=${#files[@]}
if (( total == 0 )); then
  echo "No .avi files found under: $root" >&2
  exit 1
fi

count=0
converted=0
for f in "${files[@]}"; do
  (( ++count ))
  out="${f%.*}.mp4"
  printf "File %d/%d: %s\n" "$count" "$total" "$f"

  if [[ -e $out ]]; then
    echo "  Skipping, output exists: $out"
    continue
  fi

  dur=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)

  if ffmpeg_bar "$dur" "${hwaccel[@]}" -i "$f" \
      "${vflags[@]}" -c:a aac -b:a 192k -max_muxing_queue_size 4096 "$out"; then
    (( ++converted ))
  else
    echo "  Failed: $f" >&2
    rm -f "$out"
  fi
done

echo "Converted $converted of $total file(s)."
