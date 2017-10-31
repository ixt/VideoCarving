#!/bin/bash
SUBS=$1
VIDEO=$2
TEMPWORDS=$(mktemp)
TEMPTIMES=$(mktemp)
WORKINGDIR=$(dirname $0)
ID=$(basename $SUBS | sed -e "s/\..*//g")
cd $WORKINGDIR
echo "" > $TEMPTIMES

# TODO:
#   [ ]: Better Colored Output
#   [ ]: More options & finetuning
#   [ ]: More precise mode that auto adjusts a few times
#   [ ]: Autocompile the binaries
#   [ ]: Look for libraries that are needed
#   [ ]: Move all processing to RAM to help prevent needless disk wear
#   [ ]: Implement better file globbing
#   [ ]: Modularise code into functions more & move to more native bash functions

millis_to_stamp(){
    seek="${1/./}"
    millis=$(printf %03d "$(bc -l <<< "scale=0;$seek % 1000")")
    seek=$(bc -l <<< "scale=0;($seek - $millis)/1000")
    seconds=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    seek=$(bc -l <<< "scale=0;($seek - $seconds)/60")
    minutes=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    hours=$(printf %02d "$(bc -l <<< "scale=0;($seek - $minutes)/60")")
    echo ${hours:=00}:${minutes:=00}:${seconds:=00}.${millis:=000}
}

# Clean Off Header 
LANG=$(head "$SUBS" | grep Language | head -1 | cut -d":" -f2 | xargs echo)
if [[ "$LANG" == "en" ]]; then
    if [[ ! $QUIET ]]; then echo "[*] Cleaning Header - en (auto generated)"; fi
    HEADEREND=$(sed -n "/##/=" "$SUBS")
    tail -n+$(( HEADEREND + 3 )) "$SUBS" >> $TEMPWORDS
    sed -i -e "/-->/d;s/<c\.color[0-F]*>//g;s/<[0-9.:/c]*>//g;s/ /\n/g;s/\[Music\]//g" $TEMPWORDS
    sed -i -e "/^$/d" $TEMPWORDS
else
    tail -n+5 "$SUBS" | sed -e "/-->/d;s/\*.*[^*]\*//g;/^$/d" -e "s/[[:space:]]/\n/g" | sed -e "s/[[:punct:]]*//g" -e "/^$/d" >> $TEMPWORDS
fi

# Make a ordered list of the words in the subtitles
sed -i $TEMPWORDS -e "s/[<>]/\n/g"  
sed -i $TEMPWORDS -e "/^\([[:space:]]*\|c\|\/c\)$/d;/[:.]/d;s/ //"

# Uses aeneas to enforce title syncronisation
python -m aeneas.tools.execute_task "$VIDEO" "$TEMPWORDS" "task_language=eng|os_task_file_format=csv|is_text_type=plain" $TEMPTIMES

SUCESSES=0
FAILURES=0
ERRORS=0
TEMPVIDEOFILE=$(mktemp --suffix=.mp4)
TEMPAUDIOFILE=$(mktemp --suffix=.wav)
if [ ! $QUIET ]; then echo "[*] Video Cutting"; fi
for occurance in $(cat $TEMPTIMES); do 
    # mpv "$VIDEO" --start ${millis[1]} --end ${millis[2]} --really-quiet

    stamp[0]=$(millis_to_stamp `cut -d, -f2 <<< "$occurance"`)
    stamp[1]=$(millis_to_stamp $(bc -l <<< "scale=0;`cut -d, -f3 <<< "$occurance"`-`cut -d, -f2 <<< "$occurance"`"))
    stamp[2]=$(cut -d, -f4 <<< "$occurance" | sed -e "s/\"//g")

    if grep "^${stamp[2]}$" corpus.txt -q; then
        # echo "[*] Stamp output: ${stamp[0]} ${stamp[1]} ${stamp[2]}"
        ffmpeg -loglevel panic -ss "${stamp[0]}" -i "$VIDEO" -ss 00:00:00 -t ${stamp[1]} \
        -async 1 -c:v mpeg4 -q:v 1 -c:a aac -q:a 100 "${TEMPVIDEOFILE}" -y >/dev/null 2>&1
        ffmpeg -loglevel panic -i "${TEMPVIDEOFILE}" -vn "${TEMPAUDIOFILE}" -y >/dev/null 2>&1
        RESULT=$(./RecogniseAudio.pyo --file-name "${TEMPAUDIOFILE}")
        if [[ "$RESULT" == "${stamp[2]}" ]]; then
            : (( SUCESSES += 1 ))
            echo "[*] Match: \"$RESULT\""
            HASH=$(sha1sum "$TEMPVIDEOFILE" | cut -d" " -f1)
            cp "$TEMPVIDEOFILE" "cuts/${stamp[2]}+$HASH+$ID.mp4"
        elif [[ "$RESULT" == "" ]]; then
            echo "[ERRR] No words found in audio"
            : (( ERROR += 1 ))
        elif [[ "$RESULT" == "Error reading audio" ]]; then
            echo "[ERRR] Audio probably too short: \"$occurance\""
            : (( ERROR += 1 ))
        else
            echo "[FAIL] Not a Match: \"${stamp[2]}\" vs \"$RESULT\""
            : (( FAILURES += 1 ))
        fi
    fi
done

echo "$SUCESSES Sucesses, $ERRORS Errors, $FAILURES Failures"
