#!/usr/bin/env bash
# Recursively convert every .avi file in a folder to .mp4 using GPU acceleration.
# Usage: avi2mp4.sh [-f|--force] [folder]   (folder defaults to current directory)
# Output is written next to each source file as <name>.mp4; sources are left untouched.
# By default existing .mp4 outputs are skipped; pass -f/--force to overwrite them.

set -euo pipefail

force=0
root="."
while (( $# )); do
  case "$1" in
    -f|--force) force=1 ;;
    -h|--help)
      echo "Usage: avi2mp4.sh [-f|--force] [folder]" >&2; exit 0 ;;
    --) shift; root="${1:-.}"; break ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) root="$1" ;;
  esac
  shift
done

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
        if [[ "${out_us:-}" =~ ^[0-9]+$ && "${total_us:-0}" =~ ^[0-9]+$ && $out_us -gt 0 && $total_us -gt 0 ]]; then
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

# Bits-per-pixel cap for NVENC's VBR ceiling, calibrated so a 1280x720@50 file
# caps around 8 Mbps; scaled per-file by actual width*height*fps below.
nvenc_bpp="0.17"

# compute_maxrate <width> <height> <fps> -> echoes "<maxrate_bps> <bufsize_bps>"
# Scales the NVENC -maxrate/-bufsize ceiling to each file's resolution and frame
# rate, so the cap doesn't starve high-res/high-fps sources or sit needlessly
# loose on small ones.
compute_maxrate() {
  local w="$1" h="$2" fps="$3" rate
  rate=$(awk -v w="$w" -v h="$h" -v fps="$fps" -v bpp="$nvenc_bpp" \
    'BEGIN { r = w * h * fps * bpp; if (r < 2000000) r = 2000000; printf "%d", r }')
  echo "$rate $(( rate * 2 ))"
}

# Pick a GPU H.264 encoder, mirroring video_merge_files_gpu.sh.
# Capture the encoder list once; piping ffmpeg straight into `grep -q` can make
# ffmpeg die on SIGPIPE and, under `set -o pipefail`, falsely report "not found".
encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)
vflags=()
hwaccel=()
encoder_kind=""
if grep -q '\<h264_nvenc\>' <<<"$encoders"; then
  hwaccel=(-hwaccel cuda)
  vflags=(-c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 23 -b:v 0 -spatial_aq 1 -temporal_aq 1)
  encoder_kind="nvenc"
  echo "Using NVIDIA NVENC"
elif grep -q '\<h264_qsv\>' <<<"$encoders"; then
  hwaccel=(-hwaccel qsv)
  vflags=(-c:v h264_qsv -preset veryslow -global_quality 23 -look_ahead 1)
  echo "Using Intel QuickSync"
elif grep -q '\<h264_vaapi\>' <<<"$encoders"; then
  vflags=(-vaapi_device /dev/dri/renderD128 -vf format=nv12,hwupload -c:v h264_vaapi -qp 23)
  echo "Using VAAPI"
elif grep -q '\<h264_amf\>' <<<"$encoders"; then
  vflags=(-c:v h264_amf -quality quality -rc cqp -qp_i 23 -qp_p 23 -qp_b 23)
  echo "Using AMD AMF"
elif grep -q '\<h264_videotoolbox\>' <<<"$encoders"; then
  hwaccel=(-hwaccel videotoolbox)
  vflags=(-c:v h264_videotoolbox -q:v 50)
  echo "Using VideoToolbox"
else
  vflags=(-c:v libx264 -preset medium -crf 23)
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

  if [[ -e $out && $force -eq 0 ]]; then
    echo "  Skipping, output exists: $out (use -f to overwrite)"
    continue
  fi

  dur=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)

  file_vflags=("${vflags[@]}")
  if [[ $encoder_kind == nvenc ]]; then
    read -r vid_w vid_h vid_fps < <(ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height,r_frame_rate \
      -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null | \
      awk 'NR==1{w=$0} NR==2{h=$0} NR==3{split($0,a,"/"); fps=(a[2]>0)?a[1]/a[2]:25; print w, h, fps}')
    if [[ -n "${vid_w:-}" && -n "${vid_h:-}" && -n "${vid_fps:-}" ]]; then
      read -r maxrate bufsize < <(compute_maxrate "$vid_w" "$vid_h" "$vid_fps")
      file_vflags+=(-maxrate "${maxrate}" -bufsize "${bufsize}")
    fi
  fi

  overwrite=(-n)
  [[ $force -eq 1 ]] && overwrite=(-y)
  if ffmpeg_bar "$dur" "${overwrite[@]}" "${hwaccel[@]}" -i "$f" \
      "${file_vflags[@]}" -c:a aac -b:a 192k -max_muxing_queue_size 4096 "$out"; then
    (( ++converted ))
  else
    echo "  Failed: $f" >&2
    rm -f "$out"
  fi
done

echo "Converted $converted of $total file(s)."
