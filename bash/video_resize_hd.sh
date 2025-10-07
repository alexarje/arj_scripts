#!/bin/bash

#Resize all video files to Full HD and recompress

for i in *.mp4 *.MP4; do 
    name=$(echo "$i" | cut -d'.' -f1)
    ffmpeg -hwaccel cuda -i "$i" -vf scale=1920:1080,fps=25 -c:v h264_nvenc -preset fast -b:v 5M -c:a copy "${name}_hd.mp4"
done
