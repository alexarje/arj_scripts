#!/bin/bash

# Directory containing image files
IMAGE_DIR="/path/to/your/images"

# Verify the path and replace with your actual image directory path
echo "Processing images in directory: $IMAGE_DIR"

# Check if the directory exists
if [ ! -d "$IMAGE_DIR" ]; then
  echo "The directory '$IMAGE_DIR' does not exist. Please check the path."
  exit 1
fi

# Find and process all jpg, jpeg, and png files
find "$IMAGE_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -exec bash -c '
    for image; do
        echo "Processing JPEG $image"
        # Automatically rotate images based on EXIF orientation
        jhead -autorot "$image" 2> /dev/null # Suppress errors for non-jpeg files

        # Resize the image so the longest side is 1920 pixels (implied overwrite by using the same filename)
        mogrify -resize "1920x1920>" "$image"

        # Optimize the resized image for screen use without stripping EXIF data
        jpegoptim --all-progressive --max=80 "$image"
    done
' bash {} +

find "$IMAGE_DIR" -type f -iname '*.png' -exec bash -c '
    for image; do
        echo "Processing PNG $image"
        # Optimize PNG image
        optipng -o7 "$image"
    done
' bash {} +
