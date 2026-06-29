#!/bin/bash
# Resize all JPG images in a folder to 640px width and save as _640px.jpg
# Usage: ./resize-images.sh <folder> [quality]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Defaults
TARGET_WIDTH=640
QUALITY="${2:-90}"

# Usage: resize-images.sh [folder] [quality]
INPUT_DIR="${1:-.}"

draw_bar() {
    local cur=$1 total=$2 width=40 bar="" j pct filled
    pct=$(( total > 0 ? cur * 100 / total : 100 ))
    filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do [[ $j -lt $filled ]] && bar+="#" || bar+=" "; done
    printf "\r  [%s] %3d%% (%d/%d)" "$bar" "$pct" "$cur" "$total"
}

# Validate directory
if [[ ! -d "$INPUT_DIR" ]]; then
    echo -e "${RED}Error: Directory '$INPUT_DIR' not found${NC}"
    exit 1
fi

# Check for jpg files
JPG_COUNT=$(find "$INPUT_DIR" -maxdepth 1 -iname "*.jpg" | wc -l)
if [[ $JPG_COUNT -eq 0 ]]; then
    echo -e "${RED}Error: No JPG files found in $INPUT_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}=== Resize JPG Images to ${TARGET_WIDTH}px Width ===${NC}"
echo "Directory: $INPUT_DIR"
echo "Quality: $QUALITY%"
echo "Found: $JPG_COUNT JPG files"
echo ""

mapfile -t jpgs < <(find "$INPUT_DIR" -maxdepth 1 -iname "*.jpg" -type f)

# Drop files that already carry the _640px suffix.
todo=()
for jpg in "${jpgs[@]}"; do
    [[ -z "$jpg" || "$jpg" =~ _640px\.jpg$ ]] && continue
    todo+=("$jpg")
done

total=${#todo[@]}
count=0
failed=()
for jpg in "${todo[@]}"; do
    FILENAME=$(basename "$jpg")
    BASENAME="${FILENAME%.*}"
    OUTPUT_JPG="$INPUT_DIR/${BASENAME}_640px.jpg"

    if convert "$jpg" -resize "${TARGET_WIDTH}x>" -quality "$QUALITY" "$OUTPUT_JPG" 2>/dev/null; then
        ((count++))
    else
        failed+=("$FILENAME")
    fi
    draw_bar "$(( count + ${#failed[@]} ))" "$total"
done
echo ""

for f in "${failed[@]}"; do
    echo -e "${RED}✗ Failed to resize: $f${NC}"
done

echo ""
echo -e "${GREEN}=== Complete ===${NC}"
echo "Resized: $count images"
echo "Output files have _640px.jpg suffix"

