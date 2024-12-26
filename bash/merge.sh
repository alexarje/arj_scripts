# Create list of files
printf "file '%s'\n" *.MTS > mylist.txt
# Concatenate files
ffmpeg -f concat -safe 0 -i mylist.txt output.mp4