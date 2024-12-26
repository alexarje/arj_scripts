#!/bin/bash

# Directory containing .WAV and .wav files
input_dir="."
output_file="output.flac"

# Temporary file list to store input files for concatenation
file_list="files.txt"

# Create or clear the file list
> $file_list

# Adding each .WAV and .wav file to the file list
for wav_file in "$input_dir"/*.{WAV,wav};
do 
    if [ -f "$wav_file" ]; then
        echo "file '$wav_file'" >> $file_list
    fi
done

# Merging all WAV files, downsampling to 48 kHz, and converting to 16-bit FLAC
ffmpeg -f concat -safe 0 -i $file_list -ar 48000 -sample_fmt s16 -c:a flac "$output_file"

# Cleanup
rm $file_list

echo "Merged FLAC file created: $output_file"
