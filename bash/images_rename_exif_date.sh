#!/bin/bash
# Navigate to the folder with JPG files. Change this to your desired directory.
cd /path/to/your/folder

# Loop through all JPEG files in the directory.
for file in *.jpg *.jpeg *.JPG *.JPEG; do
    # Check if the file actually matches (in case there are no matches).
    if [ -e "$file" ]; then
        # Extract the DateTimeOriginal from EXIF data and format it as YYYYMMDD_HHMMSS.
        datetime=$(exiftool -DateTimeOriginal -d "%Y%m%d_%H%M%S" "$file" | awk -F': ' '{print $2}')
        
        # If the datetime is empty, skip this file.
        if [ -z "$datetime" ]; then
            echo "Skipping $file (no EXIF DateTimeOriginal found)"
            continue
        fi
        
        # Initialize the new file name.
        new_filename="${datetime}.jpg"
        counter=1
        
        # Check if the new file name already exists to avoid overwriting.
        while [ -e "$new_filename" ]; do
            new_filename="${datetime}_$counter.jpg"
            ((counter++))
        done
        
        # Rename the file.
        echo "Renaming $file to $new_filename"
        mv "$file" "$new_filename"
    fi
done
