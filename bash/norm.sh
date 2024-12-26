#!/bin/bash

shopt -s nullglob
IFS=$'\n'
for i in *.mp4 *.MP4 *.mov *.MOV *.flv *.webm *.m4v; do
    name=$(echo "$i" | cut -d'.' -f1)
    ffmpeg -i "$i" -c:v copy -max_muxing_queue_size 4096 -threads 4 -af "loudnorm=I=-16:LRA=11:TP=-1.5,afade=d=5,afade=d=5" "${name}_norm.mp4"
done
