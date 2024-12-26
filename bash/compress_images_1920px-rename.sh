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

# Find and process all jpg, jpeg files
find "$IMAGE_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -exec bash -c '
    for image; do
        echo "Processing JPEG $image"
        # Extracting the filename without extension
        filename="${image%.*}"
        extension="${image##*.}"

        # Create a new file name with a suffix to indicate it has been optimized
        new_image="${filename}_optimized.${extension}"

        # Automatically rotate images based on EXIF orientation and create a new file
        jhead -autorot -ft "$image" "$new_image"

        # Resize the new image file while preserving the aspect ratio
        mogrify -resize "1920x1920>" "$new_image"

        # Optimize the new resized image for screen use without stripping EXIF data
        jpegoptim --all-progressive --max=80 "$new_image"
    done
' bash {} +

# Find and process all png files
find "$IMAGE_DIR" -type f -iname '*.png' -exec bash -c '
    for image; do
        echo "Processing PNG $image"
        # Extracting the filename without extension
        filename="${image%.*}"
        extension="${image##*.}"

        # Create a new file name with a suffix to indicate it has been optimized
        new_image="${filename}_optimized.${extension}"

        # Copy the original PNG to a new file
        cp "$image" "$new_image"

        # Optimize the new PNG image file
        optipng -o7 "$new_image"
    done
' bash {} +
