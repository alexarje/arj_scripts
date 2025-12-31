#!/usr/bin/env bash
set -euo pipefail

## video_merge_files_compress_h265.sh
# Merge multiple video files (common extensions) into a single H.265 (HEVC) file.
# Features:
# - safe temp concat list (handles spaces)
# - auto-detect NVENC (uses hevc_nvenc when available) or fall back to libx265
# - CLI flags for output filename, bitrate, encoder, audio handling, overwrite
# - preserves alphabetical input order; respects common video extensions

usage() {
        cat <<EOF
Usage: $(basename "$0") [options]
Options:
    -o FILE    Output filename (default: output_h265.mp4)
    -b RATE    Video bitrate (e.g. 5M). Default: 5M
    -e ENCODER Encoder to use: auto|nvenc|libx265 (default: auto)
    -a ACTION  Audio handling: copy|aac (default: copy)
    -f         Overwrite output if exists
    -n         Dry-run: print ffmpeg command and concat list, don't execute
    -h         Show this help

Example: $(basename "$0") -o merged.mp4 -b 6M -e auto -a copy
EOF
}

OUT="output_h265.mp4"
BITRATE="5M"
ENCODER="auto"
AUDIO="copy"
OVERWRITE=0
DRY_RUN=0

while getopts ":o:b:e:a:fhn" opt; do
    case $opt in
        o) OUT="$OPTARG" ;;
        b) BITRATE="$OPTARG" ;;
        e) ENCODER="$OPTARG" ;;
        a) AUDIO="$OPTARG" ;;
        f) OVERWRITE=1 ;;
            n) DRY_RUN=1 ;;
        h) usage; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 2 ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage; exit 2 ;;
    esac
done

if [ -e "$OUT" ] && [ "$OVERWRITE" -ne 1 ]; then
        echo "Output file '$OUT' already exists. Use -f to overwrite." >&2
        exit 1
fi

# Create a temp file for concat list
CONCAT_LIST=$(mktemp --suffix .txt)
cleanup(){
        rm -f -- "$CONCAT_LIST"
}
trap cleanup EXIT INT TERM

# Find files with common video extensions (case-insensitive), sorted
shopt -s nocaseglob
exts=(mts mp4 mkv avi flv wmv webm mov mpg mpeg)
files=()
for ext in "${exts[@]}"; do
    for f in *."$ext"; do
        [ -e "$f" ] || continue
        files+=("$f")
    done
done
shopt -u nocaseglob

# Sort files alphabetically and write to concat list, escaping single quotes
if [ "${#files[@]}" -eq 0 ]; then
    echo "No input video files found in the current directory." >&2
    exit 1
fi

IFS=$'\n' sorted=($(printf "%s\n" "${files[@]}" | sort))
unset IFS
for f in "${sorted[@]}"; do
    # produce absolute path so ffmpeg can read the files even when concat file is in /tmp
    if [[ "$f" = /* ]]; then
        abs_f="$f"
    else
        abs_f="$PWD/$f"
    fi
    safe_f=$(printf "%s" "$abs_f" | sed "s/'/'\\''/g")
    printf "file '%s'\n" "$safe_f" >> "$CONCAT_LIST"
done

# Detect encoder
select_encoder() {
    if [ "$ENCODER" = "auto" ]; then
        if ffmpeg -hide_banner -encoders 2>&1 | grep -qi "hevc_nvenc"; then
            echo "hevc_nvenc"
            return
        fi
        # fallback to libx265 if available
        if ffmpeg -hide_banner -encoders 2>&1 | grep -qi "libx265"; then
            echo "libx265"
            return
        fi
        # last resort: libx264 (H.264)
        if ffmpeg -hide_banner -encoders 2>&1 | grep -qi "libx264"; then
            echo "libx264"
            return
        fi
        echo "mpeg4"
    else
        case "$ENCODER" in
            nvenc) echo "hevc_nvenc" ;;
            libx265) echo "libx265" ;;
            libx264) echo "libx264" ;;
            *) echo "$ENCODER" ;;
        esac
    fi
}

ENC=$(select_encoder)
echo "Using encoder: $ENC"

# Build ffmpeg args
FFMPEG_ARGS=( -f concat -safe 0 -i "$CONCAT_LIST" )

if [ "$AUDIO" = "copy" ]; then
    FFMPEG_ARGS+=( -c:a copy )
else
    FFMPEG_ARGS+=( -c:a aac -b:a 192k )
fi

# Video encoder options
if [ "$ENC" = "hevc_nvenc" ]; then
    # use nvenc hardware encoder
    FFMPEG_ARGS+=( -c:v hevc_nvenc -preset fast -b:v "$BITRATE" )
elif [ "$ENC" = "libx265" ]; then
    FFMPEG_ARGS+=( -c:v libx265 -preset fast -b:v "$BITRATE" )
elif [ "$ENC" = "libx264" ]; then
    FFMPEG_ARGS+=( -c:v libx264 -preset fast -b:v "$BITRATE" )
else
    FFMPEG_ARGS+=( -c:v "$ENC" -b:v "$BITRATE" )
fi

if [ "$OVERWRITE" -eq 1 ]; then
    FFMPEG_ARGS+=( -y )
fi

FFMPEG_ARGS+=( "$OUT" )

echo "Merging files listed in $CONCAT_LIST into $OUT"
echo "ffmpeg ${FFMPEG_ARGS[*]}"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "--- concat list ---"
    sed -n '1,200p' "$CONCAT_LIST" || true
    echo "--- end concat list ---"
    echo "Dry-run enabled; not executing ffmpeg."
else
    ffmpeg "${FFMPEG_ARGS[@]}"
fi

echo "Done. Output: $OUT"