#!/usr/bin/env bash
# Recursively convert WAV/AIFF files to FLAC (lossless, typically ~50% smaller),
# preserving sample rate, bit depth, and channels. Output is written next to
# each source file as <name>.flac; sources are kept unless --delete-originals
# is given, and then a source is only deleted after its FLAC has been verified
# (duration match). 32-bit float sources are skipped: FLAC only stores integer
# PCM, so converting them would not be lossless.
# Usage: archive_wav2flac.sh [options] [folder]   (folder defaults to .)
#   --delete-originals   delete each source after successful, verified conversion
#   --force              overwrite existing .flac outputs (default: skip them)

set -euo pipefail

delete_originals=0
force=0
root="."

usage() {
  echo "Usage: archive_wav2flac.sh [--delete-originals] [--force] [folder]" >&2
}

while (( $# )); do
  case "$1" in
    --delete-originals) delete_originals=1 ;;
    -f|--force) force=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *) root="$1" ;;
  esac
  shift
done

[[ -d $root ]] || { echo "Not a directory: $root" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found" >&2; exit 1; }

human() { numfmt --to=iec --suffix=B "${1:-0}"; }

probe_dur() {
  ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null
}

mapfile -d '' -t files < <(find "$root" -type f \
  \( -iname '*.wav' -o -iname '*.aiff' -o -iname '*.aif' \) -print0 2>/dev/null)

total=${#files[@]}
if (( total == 0 )); then
  echo "No WAV/AIFF files found under: $root" >&2
  exit 1
fi
echo "Found $total WAV/AIFF file(s) under: $root"

count=0
converted=0
skipped=0
failed=0
saved=0
for f in "${files[@]}"; do
  (( ++count ))
  out="${f%.*}.flac"
  printf 'File %d/%d: %s\n' "$count" "$total" "$f"

  if [[ -e $out && $force -eq 0 ]]; then
    echo "  Skipping, output exists: $out (use --force to overwrite)"
    (( ++skipped )); continue
  fi

  codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || true)
  if [[ ${codec:-} == pcm_f* ]]; then
    echo "  Skipping, 32-bit float source (FLAC cannot store this losslessly): $codec"
    (( ++skipped )); continue
  fi

  overwrite=(-n); (( force )) && overwrite=(-y)
  if ! ffmpeg -hide_banner -loglevel error "${overwrite[@]}" -i "$f" \
      -map 0:a -c:a flac -compression_level 8 "$out"; then
    echo "  Failed to convert: $f" >&2
    rm -f -- "$out"
    (( ++failed )); continue
  fi

  # Verify the conversion before trusting it: durations must match closely.
  dur_src=$(probe_dur "$f"); dur_out=$(probe_dur "$out")
  if ! awk -v a="${dur_src:-0}" -v b="${dur_out:-0}" \
      'BEGIN { d = a - b; if (d < 0) d = -d; exit !(a > 0 && d <= 0.2) }'; then
    echo "  Duration mismatch (src ${dur_src:-?}s vs flac ${dur_out:-?}s) - keeping both" >&2
    (( ++failed )); continue
  fi

  sz_src=$(stat -c%s -- "$f" 2>/dev/null || echo 0)
  sz_out=$(stat -c%s -- "$out" 2>/dev/null || echo 0)
  saved=$(( saved + sz_src - sz_out ))
  (( ++converted ))
  printf '  OK: %s -> %s' "$(human "$sz_src")" "$(human "$sz_out")"
  if (( delete_originals )); then
    rm -f -- "$f" && printf ', original deleted'
  fi
  printf '\n'
done

echo
echo "Converted $converted of $total file(s), skipped $skipped, failed $failed."
echo "Space saved: $(human "$saved")$( (( delete_originals )) || echo ' (once originals are removed)')"
(( delete_originals )) || echo "Originals were kept; re-run with --delete-originals to remove them after verification."
exit 0
