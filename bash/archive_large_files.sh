#!/usr/bin/env bash
# Scan a drive/folder for large files and report which could be deleted or
# optimized. Videos are inspected with ffprobe (if installed): codec, resolution
# and bitrate are shown, and files in older codecs (h264, mpeg4, prores, ...) or
# with very high bitrates are flagged as re-encode candidates with an estimated
# saving. Nothing is ever deleted - this script only reports.
# Usage: archive_large_files.sh [options] <folder>
#   --min-size SIZE   minimum file size to report (default 500M; find(1) syntax,
#                     e.g. 100M, 2G)
#   --top N           only show the N largest files (default: all)
set -euo pipefail

min_size="500M"
top=0
root=""

usage() {
  echo "Usage: archive_large_files.sh [--min-size 500M] [--top N] <folder>" >&2
}

while (( $# )); do
  case "$1" in
    --min-size) shift; min_size="${1:?--min-size needs a value}" ;;
    --top) shift; top="${1:?--top needs a number}" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *) root="$1" ;;
  esac
  shift
done

[[ -n $root ]] || { usage; exit 1; }
[[ -d $root ]] || { echo "Not a directory: $root" >&2; exit 1; }

have_ffprobe=0
command -v ffprobe >/dev/null && have_ffprobe=1
(( have_ffprobe )) || echo "Note: ffprobe not found - videos will be listed but not analyzed." >&2

human() { numfmt --to=iec --suffix=B "${1:-0}"; }

is_video() {
  case "${1##*.}" in
    [mM][pP]4|[mM][oO][vV]|[aA][vV][iI]|[mM][kK][vV]|[mM][tT][sS]|[mM]2[tT][sS]|\
    [wW][mM][vV]|[fF][lL][vV]|[wW][eE][bB][mM]|[mM][pP][gG]|[mM][pP][eE][gG]|\
    [mM]4[vV]|3[gG][pP]|[iI][nN][sS][vV]) return 0 ;;
    *) return 1 ;;
  esac
}

echo "Scanning: $root for files larger than $min_size (this can take a while)"

# Stream the scan: large files come out prefixed "M<TAB><size><TAB><path>";
# every directory emits a bare "S" tick so the live counter below keeps moving
# even while nothing is matching.
matches=()
scanned=0
scan_progress() {
  printf '\r\033[K  %d folder(s) scanned, %d large file(s) found' \
    "$scanned" "${#matches[@]}" >&2
}
while IFS= read -r -d '' rec; do
  if [[ $rec == M$'\t'* ]]; then
    matches+=("${rec#M$'\t'}")
    scan_progress
  else
    (( ++scanned % 100 == 0 )) && scan_progress
  fi
done < <(find "$root" \
  \( -type f -size +"$min_size" -printf 'M\t%s\t%p\0' \) -o \
  \( -type d -printf 'S\0' \) \
  2>/dev/null || true)
scan_progress
echo >&2

if (( ${#matches[@]} == 0 )); then
  echo "No files larger than $min_size found under: $root"
  exit 0
fi

# Sort the "size<TAB>path" entries largest first.
mapfile -d '' -t entries < <(printf '%s\0' "${matches[@]}" | sort -z -t $'\t' -k1,1nr)

if (( top > 0 && top < ${#entries[@]} )); then
  echo "Showing the $top largest of ${#entries[@]} file(s)."
  entries=("${entries[@]:0:$top}")
fi

# Codecs where a re-encode to H.265/AV1 typically halves the size.
legacy_codec() {
  case "$1" in
    h264|mpeg4|msmpeg4v*|mpeg2video|mpeg1video|vc1|wmv*|prores|dnxhd|mjpeg|rawvideo|dvvideo|huffyuv|cinepak) return 0 ;;
    *) return 1 ;;
  esac
}

total_bytes=0
video_bytes=0
save_bytes=0
declare -A ext_bytes=() ext_count=()

echo
idx=0
for e in "${entries[@]}"; do
  (( ++idx ))
  sz="${e%%$'\t'*}"
  p="${e#*$'\t'}"
  total_bytes=$(( total_bytes + sz ))
  ext="${p##*.}"; [[ $ext == "$p" ]] && ext="(none)"
  ext=$(tr '[:upper:]' '[:lower:]' <<<"$ext")
  ext_bytes[$ext]=$(( ${ext_bytes[$ext]:-0} + sz ))
  ext_count[$ext]=$(( ${ext_count[$ext]:-0} + 1 ))

  note=""
  if is_video "$p"; then
    video_bytes=$(( video_bytes + sz ))
    if (( have_ffprobe )); then
      printf '\r\033[K  [%d/%d] analyzing: %s' "$idx" "${#entries[@]}" "$(basename -- "$p")" >&2
      # codec, width, height from the video stream; duration from the container.
      read -r codec width height < <(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name,width,height \
        -of default=noprint_wrappers=1:nokey=1 "$p" 2>/dev/null | paste -sd' ' || true)
      dur=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$p" 2>/dev/null || echo 0)
      if [[ -n ${codec:-} ]]; then
        mbps=$(awk -v s="$sz" -v d="${dur:-0}" 'BEGIN { if (d > 0) printf "%.1f", s * 8 / d / 1000000; else print "?" }')
        note="[$codec ${width:-?}x${height:-?}, ${mbps} Mbps]"
        if legacy_codec "$codec"; then
          est=$(( sz / 2 ))
          save_bytes=$(( save_bytes + est ))
          note+=" -> re-encode to H.265, save ~$(human "$est")"
        elif [[ $mbps != "?" ]] && awk -v m="$mbps" 'BEGIN { exit !(m > 30) }'; then
          est=$(( sz / 3 ))
          save_bytes=$(( save_bytes + est ))
          note+=" -> high bitrate for $codec, save ~$(human "$est")"
        fi
      else
        note="[video - unreadable by ffprobe]"
      fi
    fi
  fi

  printf '\r\033[K' >&2
  printf '%9s  %s' "$(human "$sz")" "$p"
  [[ -n $note ]] && printf '  %s' "$note"
  printf '\n'
done

echo
echo "By file type (largest first):"
for ext in "${!ext_bytes[@]}"; do
  printf '%s\t%s\t%s\n' "${ext_bytes[$ext]}" "$ext" "${ext_count[$ext]}"
done | sort -rn | while IFS=$'\t' read -r bytes ext count; do
  printf '  %-8s %6d file(s)  %8s\n' ".$ext" "$count" "$(human "$bytes")"
done

echo
echo "Total: ${#entries[@]} file(s), $(human "$total_bytes") (video: $(human "$video_bytes"))"
if (( save_bytes > 0 )); then
  echo "Estimated saving from re-encoding flagged videos: ~$(human "$save_bytes")"
  echo "Tip: video_merge_files_compress_h265.sh / avi2mp4.sh in this repo can do the re-encoding."
fi
