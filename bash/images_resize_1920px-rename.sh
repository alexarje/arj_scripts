#!/bin/bash

# Usage: images_resize_1920px-rename.sh [image_directory]
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
    filename="${image%.*}"
    extension="${image##*.}"
    new_image="${filename}_optimized.${extension}"

    # Rotate based on EXIF orientation and write to the new file.
    jhead -autorot -ft "$image" "$new_image"
    # Resize while preserving aspect ratio.
    mogrify -resize "1920x1920>" "$new_image"
    # Optimize for screen use without stripping EXIF data.
    jpegoptim --all-progressive --max=80 "$new_image" >/dev/null 2>&1
    (( ++count ))
    draw_bar "$count" "$total"
done

for image in "${pngs[@]}"; do
    filename="${image%.*}"
    extension="${image##*.}"
    new_image="${filename}_optimized.${extension}"

    cp "$image" "$new_image"
    optipng -o7 "$new_image" >/dev/null 2>&1
    (( ++count ))
    draw_bar "$count" "$total"
done
echo

echo "Processed $count image(s)."
