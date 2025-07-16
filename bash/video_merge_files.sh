# Enable case-insensitive globbing
shopt -s nocaseglob
# Create list of files
> mylist.txt
for ext in mts mp4 mkv avi flv wmv webm; do
  for file in *.$ext; do
    [ -e "$file" ] && printf "file '%s'\n" "$file" >> mylist.txt
  done
done
# Concatenate files
ffmpeg -f concat -safe 0 -i mylist.txt -c copy output.mp4
# Disable case-insensitive globbing
shopt -u nocaseglob