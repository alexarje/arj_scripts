#!/bin/bash

# Directory containing image files
IMAGE_DIR="images"

# Verify the path and replace with your actual image directory path
echo "Processing images in directory: $IMAGE_DIR"

# Check if the directory exists
if [ ! -d "$IMAGE_DIR" ]; then
  echo "The directory '$IMAGE_DIR' does not exist. Please check the path."
  exit 1
fi

find "$IMAGE_DIR" -type f -iname '*.png' -exec bash -c '
    for image; do
        echo "Processing PNG $image"
        # Optimize PNG image
        optipng -o7 "$image"
    done
' bash {} +
