#!/bin/bash

# Usage: compress-images.sh [image_directory]
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

# Collect PNG files (recursively), NUL-delimited for safe names.
mapfile -d '' -t files < <(find "$IMAGE_DIR" -type f -iname '*.png' -print0)
total=${#files[@]}
if [ "$total" -eq 0 ]; then
  echo "No PNG files found in $IMAGE_DIR."
  exit 0
fi

count=0
for image in "${files[@]}"; do
  optipng -o7 "$image" >/dev/null 2>&1
  (( ++count ))
  draw_bar "$count" "$total"
done
echo

echo "Optimized $count PNG file(s)."
