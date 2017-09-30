#!/bin/bash
SUBS=$1
VIDEO=$2
HEADEREND=$(sed -n "/##/=" "$SUBS")
WORKINGDIR=$(dirname $0)
cd $WORKINGDIR
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
    -e "/^$/d" \
    .temp

if [ ! $QUIET ]; then echo "[*] Filling in the blanks"; fi
# Not the best solution to missing stamps 
# but its the best I can think rn 
# just take the previous stamp and add it
while read LINETO; do
    LINEFROM=$(( LINETO - 1 ))
    until grep -q -E ">" <(sed -e "$LINEFROM"'!d' .temp); do
        (( LINEFROM -= 1 ))
    done
    STAMP=$(sed -e "$LINEFROM"'!d' .temp | cut -d"<" -f2 )
    sed -i -e "$LINETO"'s/$/<'"$STAMP"'/' .temp
done < <(sed -n "/[^>]$/=" .temp)  

sed -i -e "s/</|/g" -e "s/>//g" .temp

while read LINE; do
    STAMP=$(sed -e "$LINE"'!d' -e "s/:/./g" .temp | cut -d"|" -f2)
    IFS=. read -a STAMP_EL <<< "$STAMP"
    MS=$(bc -l <<< "(((((${STAMP_EL[0]} * 60) + ${STAMP_EL[1]}) * 60 ) + ${STAMP_EL[2]}) * 1000 ) + ${STAMP_EL[3]}")
    sed -i "$LINE"'s/$/|'"$MS"'/' .temp
done < <(sed -n "/|/=" .temp)

last=()
while read row; do
    IFS="|" read -a stamp <<< "$row"

    echo "Stamp: ${last[1]} to ${stamp[1]} Phrase: ${last[0]}"

    if [ ! ${last[0]} == "[Music]" ]; then
        length=$(bc -l <<< "scale=3;(${stamp[2]} - ${last[2]}) / 1000")
        if [ ! ${length} == "0" ]; then
            lengthStamp=$(printf "%12s\n" "$length" | sed -e "s/ /0/g" -e 's/./:/3;s/./:/6')
            ffmpeg -ss ${last[1]} -i "${VIDEO}" -ss 00:00:00 -to $lengthStamp -async 1 "${last[0]}.mp4"
            SHA1=$(sha1sum "${last[0]}.mp4" | cut -d" " -f 1)
            mv "${last[0]}.mp4" "cuts/${last[0]}-${SHA1}.mp4" 
        fi
    fi
    last[0]=${stamp[0]}
    last[1]=${stamp[1]}
    last[2]=${stamp[2]}
done < .temp

