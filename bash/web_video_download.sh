#!/bin/bash

# Check if URL is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <URL>"
    exit 1
fi

# URL of the web page
URL="$1"

# Directory to save the downloaded videos
OUTPUT_DIR="./videos"

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Download the web page and extract video URLs
wget -q -O - "$URL" | grep -oP '(?<=href=")[^"]*\.(mp4|avi|mov|mkv|flv|wmv|webm|mpg|mpeg)|(?<=src=")[^"]*\.(mp4|avi|mov|mkv|flv|wmv|webm|mpg|mpeg)|(?<=rel="preconnect" href=")[^"]*\.(mp4|avi|mov|mkv|flv|wmv|webm|mpg|mpeg)' | while read -r video_url; do
    # Handle relative URLs
    if [[ "$video_url" != http* ]]; then
        video_url="$URL/$video_url"
    fi
    # Download each video file
    wget -P "$OUTPUT_DIR" "$video_url"
done