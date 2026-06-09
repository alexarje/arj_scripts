#!/bin/bash
# Usage: audio_convert_flac.sh [directory] [output.flac]

set -euo pipefail
shopt -s nullglob

input_dir="${1:-.}"
output_file="${2:-output.flac}"
file_list="$(mktemp)"

if [ ! -d "$input_dir" ]; then
  echo "Error: directory not found: $input_dir" >&2
  exit 1
fi

trap 'rm -f "$file_list"' EXIT

for wav_file in "$input_dir"/*.{WAV,wav}; do
  echo "file '$wav_file'" >> "$file_list"
done

if [ ! -s "$file_list" ]; then
  echo "Error: no WAV files found in $input_dir" >&2
  exit 1
fi

ffmpeg -f concat -safe 0 -i "$file_list" -ar 48000 -sample_fmt s16 -c:a flac "$output_file"
echo "Merged FLAC file created: $output_file"
