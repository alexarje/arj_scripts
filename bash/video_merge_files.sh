#!/usr/bin/env bash

# Enable case-insensitive globbing and ignore non-matching patterns.
shopt -s nocaseglob nullglob

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

output_file="output.mp4"
force_overwrite=0
for arg in "$@"; do
  case "$arg" in
    --force|-f)
      force_overwrite=1
      ;;
    *)
      output_file="$arg"
      ;;
  esac
done

if [[ -e "$output_file" ]]; then
  if (( force_overwrite == 1 )); then
    rm -f -- "$output_file"
  else
    echo "Refusing to overwrite existing file: $output_file" >&2
    echo "Run with --force to overwrite." >&2
    exit 1
  fi
fi

list_file="$(mktemp "${TMPDIR:-/tmp}/ffmpeg-concat.XXXXXX.txt")"
trap 'rm -f "$list_file"' EXIT

added=0
total_dur=0
for ext in mts mp4 mkv avi flv wmv webm; do
  for file in *."$ext"; do
    abs_file="$PWD/$file"
    escaped_file=${abs_file//\'/\'\\\'\'}
    printf "file '%s'\n" "$escaped_file" >> "$list_file"
    d=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$file" 2>/dev/null || echo 0)
    total_dur=$(awk "BEGIN{print $total_dur + ${d:-0}}")
    ((added++))
  done
done

if (( added == 0 )); then
  echo "No matching video files found in current directory." >&2
  exit 1
fi

# Concatenate files.
# MP4 cannot store some source audio codecs (for example pcm_bluray), so
# keep video copy and transcode audio to AAC when output is MP4.
if [[ "${output_file##*.}" =~ ^([mM][pP]4)$ ]]; then
  ffmpeg_bar "$total_dur" -f concat -safe 0 -i "$list_file" -c:v copy -c:a aac -b:a 192k -movflags +faststart "$output_file"
else
  ffmpeg_bar "$total_dur" -f concat -safe 0 -i "$list_file" -c copy "$output_file"
fi

# Disable shell options we enabled.
shopt -u nocaseglob nullglob
