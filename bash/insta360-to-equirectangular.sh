#!/bin/bash
# Convert Insta360 INSP/DNG dual-fisheye to equirectangular JPG using FFmpeg
# Usage: ./insta360-to-equirectangular.sh <input_file.insp|input_dir> [hfov] [vfov]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Defaults
HFOV="${2:-204}"
VFOV="${3:-204}"
OUTPUT_WIDTH=8000
OUTPUT_HEIGHT=4000

# Check args
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Usage: $0 <input_file.insp|input_directory> [hfov] [vfov]${NC}"
    echo "Example: $0 image.insp"
    echo "         $0 ./360_images 204 204"
    echo "         $0 image.insp 206 202"
    exit 1
fi

INPUT="$1"

# Check if input is file or directory
if [[ -f "$INPUT" ]]; then
    # Single file mode
    if [[ ! "$INPUT" =~ \.(insp|INSP)$ ]]; then
        echo -e "${RED}Error: File must be .insp${NC}"
        exit 1
    fi
    INPUT_FILES=("$INPUT")
    WORKDIR=$(dirname "$INPUT")
elif [[ -d "$INPUT" ]]; then
    # Directory mode: find all .insp files
    WORKDIR="$INPUT"
    mapfile -t INPUT_FILES < <(find "$WORKDIR" -maxdepth 1 -iname "*.insp" | sort)
    if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
        echo -e "${RED}Error: No .insp files found in $WORKDIR${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: '$INPUT' not found${NC}"
    exit 1
fi

echo -e "${GREEN}=== Insta360 to Equirectangular (FFmpeg) ===${NC}"
echo "Input: $INPUT"
echo "Output directory: $WORKDIR"
echo "FOV: H=$HFOV° V=$VFOV°"
echo "Output size: ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"
echo ""
echo "Processing ${#INPUT_FILES[@]} file(s)..."
echo ""

# Process each file
for INPUT_FILE in "${INPUT_FILES[@]}"; do
    BASENAME=$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')
    
    echo -e "${YELLOW}[Processing] $BASENAME${NC}"
    
    # Step 1: Extract frame from INSP to JPG
    echo -e "${YELLOW}  [1/2] Extracting JPG from INSP...${NC}"
    TEMP_JPG="$WORKDIR/${BASENAME}_temp.jpg"
    if ! ffmpeg -i "$INPUT_FILE" -frames:v 1 "$TEMP_JPG" -y 2>/dev/null; then
        echo -e "${RED}  ✗ Failed to extract from $INPUT_FILE${NC}"
        continue
    fi
    echo -e "${GREEN}  ✓ Extracted${NC}"
    
    # Step 2: Convert to equirectangular
    echo -e "${YELLOW}  [2/2] Converting to equirectangular...${NC}"
    OUTPUT_FILE="$WORKDIR/${BASENAME}_equirect.jpg"
    if ! ffmpeg -i "$TEMP_JPG" \
        -vf "v360=input=dfisheye:output=e:ih_fov=$HFOV:iv_fov=$VFOV:w=$OUTPUT_WIDTH:h=$OUTPUT_HEIGHT:interp=lanczos" \
        -frames:v 1 "$OUTPUT_FILE" -y 2>/dev/null; then
        echo -e "${RED}  ✗ Failed to convert${NC}"
        rm -f "$TEMP_JPG"
        continue
    fi
    
    # Get dimensions
    DIMS=$(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$OUTPUT_FILE" 2>/dev/null | head -1)
    echo -e "${GREEN}  ✓ Converted to $OUTPUT_FILE ($DIMS)${NC}"
    
    # Cleanup
    rm -f "$TEMP_JPG"
done

echo ""
echo -e "${GREEN}=== Complete ===${NC}"
ls -lh "$WORKDIR"/*_equirect.jpg 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""
echo "To embed in Hugo, add to your post:"
echo '{{< panorama src="/images/2025/12/filename_equirect.jpg" height="500px" yaw=0 hfov=100 >}}'
