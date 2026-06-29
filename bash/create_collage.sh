#!/bin/bash

set -euo pipefail

# Usage: create_collage.sh [directory]
INPUT_DIR="${1:-.}"

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: directory not found: $INPUT_DIR" >&2
    exit 1
fi
BASE_NAME="collage"
EXT="png"
COLUMNS=5
ROWS=8

draw_bar() {
    local cur=$1 total=$2 width=40 bar="" j pct filled
    pct=$(( total > 0 ? cur * 100 / total : 100 ))
    filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do [[ $j -lt $filled ]] && bar+="#" || bar+=" "; done
    printf "\r  [%s] %3d%% (%d/%d)" "$bar" "$pct" "$cur" "$total"
}

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

echo "Creating $COLLAGE_COUNT collage(s) from $FILE_COUNT image(s)..."
created=()
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

    montage "${CHUNK[@]}" -tile "${COLUMNS}x${CHUNK_ROWS}" -geometry +0+0 "$OUTPUT_FILE"
    created+=("$OUTPUT_FILE ($CHUNK_COUNT files, ${COLUMNS}x${CHUNK_ROWS})")
    draw_bar "$((c+1))" "$COLLAGE_COUNT"
done
echo

for c in "${created[@]}"; do
    echo "Collage created: $c"
done
