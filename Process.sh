#!/bin/bash
SUBS=$1
VIDEO=$2
HEADEREND=$(sed -n "/##/=" "$SUBS")
WORKINGDIR=$(dirname $0)
cd $WORKINGDIR
mkdir .cuts
touch .temp
echo "" > .temp
# Clean Off Header 
if [ ! $QUIET ]; then echo "[*] Cleaning Header"; fi
tail +$(( HEADEREND + 3 )) "$SUBS" >> .temp

# Clean Gunk
sed -i -e "/-->/d" \
    -e "s/<c>//g" \
    -e "s/<\/c>//g" \
    -e "s/<c.color[0-F]*[^>]>//g" \
    -e "s/[[:space:]]//g" \
    -e "s/>/>\n/g" \
    .temp

sed -i \
    -e "/[^>]$/d" \
    -e "/^$/d" \
    -e "s/</|/g" \
    -e "s/>//g" \
    .temp

# making timestamps into millis since start
while read LINE; do
    STAMP=$(sed -e "$LINE"'!d' -e "s/:/./g" .temp | cut -d"|" -f2)
    IFS=. read -a STAMP_EL <<< "$STAMP"
    MS=$(bc -l <<< "(((((${STAMP_EL[0]} * 60) + ${STAMP_EL[1]}) * 60 ) + ${STAMP_EL[2]}) * 1000 ) + ${STAMP_EL[3]}")
    sed -i "$LINE"'s/$/|'"$MS"'/' .temp
done < <(sed -n "/|/=" .temp)

TIMEBEFORE="30"
while read row; do
    IFS="|" read -a stamp <<< "$row"
    inputmillis=${stamp[2]}
    word=${stamp[0]}
    seek=$(bc -l <<< "$inputmillis - $TIMEBEFORE")
    millis=$(printf %03d "$(bc -l <<< "scale=0;$seek % 1000")")
    seek=$(bc -l <<< "scale=0;($seek - $millis)/1000")
    seconds=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    seek=$(bc -l <<< "scale=0;($seek - $seconds)/60")
    minutes=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    hours=$(printf %02d "$(bc -l <<< "scale=0;($seek - $minutes)/60")")
    stamp=$(echo $hours:$minutes:$seconds.$millis)
    #ffmpeg -ss "$stamp" -i "$VIDEO" -ss 00:00:00 -t 0.3 -async 1 -c:v mpeg4 -q:v 1 -c:a aac -q:a 100 $word.mp4 
    ffmpeg -ss "$stamp" -i "$VIDEO" -ss 00:00:00 -t 0.3 -c copy cuts/$word.mp4 
    #SHA1=$(sha1sum $word.mp4 | cut -d" " -f 1)
    #mv $word.mp4 cuts/$word-$SHA1.mp4
done < .temp
