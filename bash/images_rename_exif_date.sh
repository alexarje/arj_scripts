#!/bin/bash
# Usage: images_rename_exif_date.sh [image_directory]
IMAGE_DIR="${1:-.}"
cd "$IMAGE_DIR" || exit 1

draw_bar() {
    local cur=$1 total=$2 width=40 bar="" j pct filled
    pct=$(( total > 0 ? cur * 100 / total : 100 ))
    filled=$(( pct * width / 100 ))
    for ((j=0; j<width; j++)); do [[ $j -lt $filled ]] && bar+="#" || bar+=" "; done
    printf "\r  [%s] %3d%% (%d/%d)" "$bar" "$pct" "$cur" "$total"
}

# Collect all JPEG files (ignore non-matching patterns).
shopt -s nullglob
files=(*.jpg *.jpeg *.JPG *.JPEG)
total=${#files[@]}
if [ "$total" -eq 0 ]; then
    echo "No JPEG files found in $IMAGE_DIR." >&2
    exit 1
fi

count=0
skipped=()
for file in "${files[@]}"; do
    (( ++count ))
    # Extract the DateTimeOriginal from EXIF data and format it as YYYYMMDD_HHMMSS.
    datetime=$(exiftool -DateTimeOriginal -d "%Y%m%d_%H%M%S" "$file" | awk -F': ' '{print $2}')

    # If the datetime is empty, skip this file.
    if [ -z "$datetime" ]; then
        skipped+=("$file")
        draw_bar "$count" "$total"
        continue
    fi

    # Build a unique new file name to avoid overwriting.
    new_filename="${datetime}.jpg"
    counter=1
    while [ -e "$new_filename" ]; do
        new_filename="${datetime}_$counter.jpg"
        ((counter++))
    done

    mv "$file" "$new_filename"
    draw_bar "$count" "$total"
done
echo

for f in "${skipped[@]}"; do
    echo "Skipped $f (no EXIF DateTimeOriginal found)"
done
echo "Renamed $(( total - ${#skipped[@]} )) of $total file(s)."
