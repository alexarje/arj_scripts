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

# Check args
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Usage: $0 <folder> [quality]${NC}"
    echo "Example: $0 ./static/images/2025/12"
    echo "         $0 ./static/images/2025/12 85"
    exit 1
fi

INPUT_DIR="$1"

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

count=0
while IFS= read -r jpg; do
    [[ -z "$jpg" ]] && continue
    
    # Skip if already has _640px suffix
    if [[ "$jpg" =~ _640px\.jpg$ ]]; then
        continue
    fi
    
    FILENAME=$(basename "$jpg")
    BASENAME="${FILENAME%.*}"
    OUTPUT_JPG="$INPUT_DIR/${BASENAME}_640px.jpg"
    
    # Get original dimensions
    ORIG_DIMS=$(identify "$jpg" 2>/dev/null | awk '{print $3}' || echo "N/A")
    ORIG_SIZE=$(ls -lh "$jpg" 2>/dev/null | awk '{print $5}' || echo "N/A")
    
    # Resize to new file
    echo -ne "  Resizing $FILENAME... "
    if convert "$jpg" -resize "${TARGET_WIDTH}x>" -quality "$QUALITY" "$OUTPUT_JPG" 2>/dev/null; then
        # Get new dimensions
        NEW_SIZE=$(ls -lh "$OUTPUT_JPG" 2>/dev/null | awk '{print $5}' || echo "N/A")
        NEW_DIMS=$(identify "$OUTPUT_JPG" 2>/dev/null | awk '{print $3}' || echo "N/A")
        
        echo -e "${GREEN}✓${NC}"
        echo -e "    Original: $ORIG_DIMS ($ORIG_SIZE)"
        echo -e "    Resized:  $NEW_DIMS ($NEW_SIZE) → ${BASENAME}_640px.jpg"
        ((count++))
    else
        echo -e "${RED}✗ Failed to resize${NC}"
    fi
done < <(find "$INPUT_DIR" -maxdepth 1 -iname "*.jpg" -type f)

echo ""
echo -e "${GREEN}=== Complete ===${NC}"
echo "Resized: $count images"
echo "Output files have _640px.jpg suffix"

