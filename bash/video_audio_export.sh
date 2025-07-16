#!/bin/bash

for i in *.mp4 *.MP4; do 
    name=`echo $i | cut -d'.' -f1`; ffmpeg -i "$i" -c copy "${name}.aac"; 
done
