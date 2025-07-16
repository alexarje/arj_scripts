#!/bin/bash

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <folder_with_png_files>"
    exit 1
fi

INPUT_DIR="$1"
BASE_NAME="collage"
EXT="png"
COLUMNS=5
ROWS=8

if ! command -v montage &> /dev/null; then
    echo "ImageMagick is not installed. Install it with: sudo apt install imagemagick"
    exit 1
fi

if [ ! -d "$INPUT_DIR" ]; then
    echo "Directory '$INPUT_DIR' not found!"
    exit 1
fi

shopt -s nullglob
FILES=("$INPUT_DIR"/*.png)
FILE_COUNT=${#FILES[@]}

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "No PNG files found in '$INPUT_DIR'"
    exit 1
fi

MAX_PER_COLLAGE=$((COLUMNS * ROWS))
COLLAGE_COUNT=$(( (FILE_COUNT + MAX_PER_COLLAGE - 1) / MAX_PER_COLLAGE ))
FOLDER_NAME=$(basename "$INPUT_DIR")

for ((c=0; c<COLLAGE_COUNT; c++)); do
    START=$((c * MAX_PER_COLLAGE))
    CHUNK=("${FILES[@]:$START:MAX_PER_COLLAGE}")
    CHUNK_COUNT=${#CHUNK[@]}
    CHUNK_ROWS=$(( (CHUNK_COUNT + COLUMNS - 1) / COLUMNS ))

    OUTPUT_FILE="${BASE_NAME}_${FOLDER_NAME}"
    [ "$COLLAGE_COUNT" -gt 1 ] && OUTPUT_FILE+="_$((c+1))"
    OUTPUT_FILE+=".${EXT}"

    i=1
    ORIG_OUTPUT_FILE="$OUTPUT_FILE"
    while [ -f "$OUTPUT_FILE" ]; do
        OUTPUT_FILE="${ORIG_OUTPUT_FILE%.*}_$i.${EXT}"
        ((i++))
    done

    echo "Creating collage $((c+1)) with $CHUNK_COUNT files. Grid: ${COLUMNS}x${CHUNK_ROWS}"
    montage "${CHUNK[@]}" -tile "${COLUMNS}x${CHUNK_ROWS}" -geometry +0+0 "$OUTPUT_FILE"
    echo "Collage created: $OUTPUT_FILE"
done
