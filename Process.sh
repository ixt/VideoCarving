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

millis_to_stamp(){
    seek="$1"
    millis=$(printf %03d "$(bc -l <<< "scale=0;$seek % 1000")")
    seek=$(bc -l <<< "scale=0;($seek - $millis)/1000")
    seconds=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    seek=$(bc -l <<< "scale=0;($seek - $seconds)/60")
    minutes=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    hours=$(printf %02d "$(bc -l <<< "scale=0;($seek - $minutes)/60")")
    echo ${hours:=00}:${minutes:=00}:${seconds:=00}.${millis:=000}
}

# making timestamps into millis since start
if [ ! $QUIET ]; then echo "[*] Time stamp to millis"; fi
while read LINE; do
    STAMP=$(sed -e "$LINE"'!d' -e "s/:/./g" .temp | cut -d"|" -f2)
    IFS=. read -a STAMP_EL <<< "$STAMP"
    MS=$(bc -l <<< "(((((${STAMP_EL[0]} * 60) + ${STAMP_EL[1]}) * 60 ) + ${STAMP_EL[2]}) * 1000 ) + ${STAMP_EL[3]}")
    sed -i "$LINE"'s/$/|'"$MS"'/' .temp
done < <(sed -n "/|/=" .temp)

TEMPVID=$(mktemp)
if [ ! $QUIET ]; then echo "[*] Millis + word length"; fi
while read row; do
    IFS="|" read -a stamp <<< "$row"
    theWord=$(echo $row | cut -d"|" -f 1 | sed -e "s/[^[:alpha:]]//g")
    inputmillis=${stamp[2]}
    wordLength=$(echo "scale=2;1*`grep "^$theWord," corpus-length.txt | cut -d, -f2`" | bc -l | cut -d. -f 1)
    endStamp=""
    startStamp=""
    if [[ "$wordLength" ]]; then
        startStamp=$(millis_to_stamp $(( inputmillis - (wordLength /2))) )
        endStamp=$(millis_to_stamp $wordLength )
        echo $startStamp,$endStamp,$theWord >> $TEMPVID
    fi
done < .temp

if [ ! $QUIET ]; then echo "[*] Video Cutting"; fi
while read row; do
    IFS="," read -a stamp <<< "$row"
    ffmpeg -ss "${stamp[0]}" -i "$VIDEO" -ss 00:00:00 -t ${stamp[1]} \
    -async 1 -c:v mpeg4 -q:v 1 -c:a aac -q:a 100 "cuts/${stamp[2]}-${stamp[0]//:/-}.mp4" -y
done < $TEMPVID
