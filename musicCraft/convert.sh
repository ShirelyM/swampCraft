
for file in "$1"/*; do  

  ~/apps/ffmpeg-git-20240629-amd64-static/ffmpeg -i  "$file" -ac 1 -c:a dfpwm "${file%.*}"".dfpwm" -ar 48k
done

cd $1
rm -rf *.mp3
