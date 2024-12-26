for i in *.mp4 *.MP4; do 
    name=`echo $i | cut -d'.' -f1`; ffmpeg -i "$i" -vf scale=1920:1080,fps=30 "${name}_hd.mp4"; 
done
