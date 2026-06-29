#!/bin/bash

# Usage: images_resize_1920px-overwrite.sh [image_directory]
IMAGE_DIR="${1:-.}"

echo "Processing images in directory: $IMAGE_DIR"

# Check if the directory exists
if [ ! -d "$IMAGE_DIR" ]; then
  echo "The directory '$IMAGE_DIR' does not exist. Please check the path."
  exit 1
fi

draw_bar() {
    local cur=$1 total=$2 width=40 bar="" j pct filled
    pct=$(( total > 0 ? cur * 100 / total : 100 ))
    filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do [[ $j -lt $filled ]] && bar+="#" || bar+=" "; done
    printf "\r  [%s] %3d%% (%d/%d)" "$bar" "$pct" "$cur" "$total"
}

# Collect JPEG and PNG files (recursively), NUL-delimited for safe names.
mapfile -d '' -t jpegs < <(find "$IMAGE_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0)
mapfile -d '' -t pngs < <(find "$IMAGE_DIR" -type f -iname '*.png' -print0)

total=$(( ${#jpegs[@]} + ${#pngs[@]} ))
if [ "$total" -eq 0 ]; then
  echo "No JPEG or PNG files found in $IMAGE_DIR."
  exit 0
fi

count=0

for image in "${jpegs[@]}"; do
    # Automatically rotate images based on EXIF orientation.
    jhead -autorot "$image" 2> /dev/null # Suppress errors for non-jpeg files
    # Resize so the longest side is 1920 pixels (overwrites in place).
    mogrify -resize "1920x1920>" "$image"
    # Optimize for screen use without stripping EXIF data.
    jpegoptim --all-progressive --max=80 "$image" >/dev/null 2>&1
    (( ++count ))
    draw_bar "$count" "$total"
done

for image in "${pngs[@]}"; do
    optipng -o7 "$image" >/dev/null 2>&1
    (( ++count ))
    draw_bar "$count" "$total"
done
echo

echo "Processed $count image(s)."
