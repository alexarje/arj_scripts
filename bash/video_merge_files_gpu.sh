#!/usr/bin/env bash
# Merge compatible video files in current directory into one output file.
# Usage: video_merge_files2.sh [output.mp4] [--reencode] [--gpu]

set -euo pipefail

out="output.mp4"
reencode=0
use_gpu=0

for arg in "$@"; do
  case "$arg" in
    --reencode) reencode=1 ;;
    --gpu) use_gpu=1 ;;
    *.mp4|*.mkv|*.mov) out="$arg" ;;
    *) out="$arg" ;;
  esac
done

command -v ffmpeg >/dev/null || { echo "ffmpeg not found"; exit 1; }

shopt -s nullglob nocaseglob
exts=(mts mp4 mkv avi flv wmv webm)
mapfile -t files < <(for e in "${exts[@]}"; do printf '%s\n' *."$e"; done)
shopt -u nocaseglob

uniq_files=()
declare -A seen
for f in "${files[@]}"; do
  [[ -f $f && -z ${seen["$f"]+x} ]] && { uniq_files+=("$f"); seen["$f"]=1; }
done

(( ${#uniq_files[@]} )) || { echo "No matching video files."; exit 1; }

mapfile -t uniq_files < <(printf '%s\n' "${uniq_files[@]}" | LC_ALL=C sort -fV)

listfile="$(mktemp)"
cleanup() { rm -f "$listfile"; }
trap cleanup EXIT

for f in "${uniq_files[@]}"; do
  abs="$(readlink -f -- "$f")"
  printf "file '%s'\n" "$abs" >> "$listfile"
done

gpu_codec=""
vflags=()
if (( use_gpu )); then
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_nvenc\>'; then
    gpu_codec="h264_nvenc"
    vflags=(-c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 19 -b:v 0 -spatial_aq 1 -temporal_aq 1)
    echo "Using NVIDIA NVENC"
  elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_qsv\>'; then
    gpu_codec="h264_qsv"
    vflags=(-c:v h264_qsv -preset veryslow -global_quality 19 -look_ahead 1)
    echo "Using Intel QuickSync"
  elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_vaapi\>'; then
    gpu_codec="h264_vaapi"
    vflags=(-vaapi_device /dev/dri/renderD128 -vf format=nv12,hwupload -c:v h264_vaapi -qp 19)
    echo "Using VAAPI"
  elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_amf\>'; then
    gpu_codec="h264_amf"
    vflags=(-c:v h264_amf -quality quality -rc cqp -qp_i 19 -qp_p 19 -qp_b 19)
    echo "Using AMD AMF"
  elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_videotoolbox\>'; then
    gpu_codec="h264_videotoolbox"
    vflags=(-c:v h264_videotoolbox -q:v 65)
    echo "Using VideoToolbox"
  else
    echo "Warning: No GPU encoder found, falling back to CPU"
  fi
fi

# Detect unsupported audio for MP4 when attempting copy
ext="${out##*.}"
need_audio_transcode=0
if [[ $ext == mp4 && $reencode -eq 0 ]]; then
  safe_audio=(aac mp3 ac3 eac3)
  declare -A safe_map
  for c in "${safe_audio[@]}"; do safe_map["$c"]=1; done
  for f in "${uniq_files[@]}"; do
    while IFS= read -r ac; do
      [[ -n $ac && -z ${safe_map["$ac"]+x} ]] && need_audio_transcode=1
    done < <(ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$f" || true)
  done
  (( need_audio_transcode )) && echo "Non-MP4 audio codec detected; will transcode audio to AAC."
fi

if (( reencode )); then
  if [[ -z $gpu_codec ]]; then
    vflags=(-c:v libx264 -preset medium -crf 18)
    echo "Using CPU encoding (libx264)"
  fi
  ffmpeg -hide_banner -loglevel info -f concat -safe 0 -i "$listfile" \
    "${vflags[@]}" -c:a aac -b:a 192k "$out"
else
  if (( need_audio_transcode )); then
    ffmpeg -hide_banner -loglevel info -f concat -safe 0 -i "$listfile" \
      -c:v copy -c:a aac -b:a 192k "$out" || { echo "Failed."; exit 1; }
  else
    if ! ffmpeg -hide_banner -loglevel warning -f concat -safe 0 -i "$listfile" -c copy "$out"; then
      echo "Stream copy failed; retrying with reencode."
      if [[ -z $gpu_codec ]] && (( use_gpu )); then
        if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q '\<h264_nvenc\>'; then
          vflags=(-c:v h264_nvenc -preset p5 -rc vbr -cq 20 -b:v 0)
        else
          vflags=(-c:v libx264 -preset medium -crf 20)
        fi
      elif [[ -z $gpu_codec ]]; then
        vflags=(-c:v libx264 -preset medium -crf 20)
      fi
      ffmpeg -hide_banner -loglevel info -f concat -safe 0 -i "$listfile" \
        "${vflags[@]}" -c:a aac -b:a 160k "$out"
    fi
  fi
fi

echo "Created: $out"