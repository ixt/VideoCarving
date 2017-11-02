#!/bin/bash
# TODO:
#   [*]: JSON info file for every downloaded video
#   [~]: More precise mode that auto adjusts a few times
#   [ ]: Implement Soundex to try before auto adjustments
#   [ ]: Implement inital load of corpus to remove terms that are already to 1000 terms
#   [ ]: Look for libraries that are needed
#   [ ]: Install script for apt systems
#   [ ]: Fix options

dusage() {
echo <<EOS
Option not found

Usage: Process.sh [options] [arguments]

Cuts video+subtitles into single word video clips

Options:
    -o <dir>    output directory
    -q          quiet
    -h          this screen
    -r          make a ramdisk
    -v          input video
    -s          input subs
    -i          youtube download with id          
EOS
exit 1
}

usage() {
echo <<EOS
Usage: Process.sh [options] [arguments]

Cuts video+subtitles into single word video clips

Options:
    -o <dir>    output directory
    -q          quiet
    -h          this screen
    -r          make a ramdisk
    -v          input video
    -s          input subs
    -i          youtube download with id          
EOS
exit 0
}

millis_to_stamp(){
    local seek=$(cut -d. -f1 <<< "$1")
    local millis=$(printf %03d "$(bc -l <<< "scale=0;$seek % 1000")")
    local seek=$(bc -l <<< "scale=0;($seek - $millis)/1000")
    local seconds=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    local seek=$(bc -l <<< "scale=0;($seek - $seconds)/60")
    local minutes=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    local hours=$(printf %02d "$(bc -l <<< "scale=0;($seek - $minutes)/60")")
    echo ${hours:=00}:${minutes:=00}:${seconds:=00}.${millis:=000}
}

aenas_based_stamps(){
    echo "" > $TEMPTIMES
    
    # Clean Off Header 
    LANG=$(head "$SUBS" | grep Language | head -1 | cut -d":" -f2 | xargs echo)
    if [[ "$LANG" == "en" ]]; then
        if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Cleaning Subs - en (auto generated)"; fi
        HEADEREND=$(sed -n "/##/=" "$SUBS")
        tail -n+$(( HEADEREND + 3 )) "$SUBS" >> $TEMPWORDS
        sed -i -e "/-->/d;s/<c\.color[0-F]*>//g;s/<[0-9.:/c]*>//g;s/ /\n/g;s/\[Music\]//g" $TEMPWORDS
        sed -i -e "/^$/d" $TEMPWORDS
    else
        if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Cleaning Subs - en or other"; fi
        tail -n+5 "$SUBS" | sed -e "/-->/d;s/\*.*[^*]\*//g;/^$/d" -e "s/[[:space:]]/\n/g" | sed -e "s/[[:punct:]]*//g" -e "/^$/d" >> $TEMPWORDS
    fi
    
    # Make a ordered list of the words in the subtitles
    sed -i $TEMPWORDS -e "s/[<>]/\n/g"  
    sed -i $TEMPWORDS -e "/^\([[:space:]]*\|c\|\/c\)$/d;/[:.]/d;s/ //"
    
    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Using Aeneas to realign subs"; fi
    # Uses aeneas to enforce title syncronisation
    python -m aeneas.tools.execute_task "$VIDEO" "$TEMPWORDS" "task_language=eng|os_task_file_format=csv|is_text_type=plain" $TEMPTIMES
}

espeak_based_stamps(){
    # Clean Off Header 
    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Cleaning Subs"; fi
    tail +$(( `sed -n "/##/=" "$SUBS"` + 3 )) "$SUBS" >> "$TEMPWORDS"
    
    # Clean Gunk
    sed -i -e "/-->/d" \
        -e "s/<c>//g" \
        -e "s/<\/c>//g" \
        -e "s/<c.color[0-F]*[^>]>//g" \
        -e "s/[[:space:]]//g" \
        -e "s/>/>\n/g" \
        "$TEMPWORDS"
    
    sed -i \
        -e "/[^>]$/d" \
        -e "/^$/d" \
        -e "s/</|/g" \
        -e "s/>//g" \
        "$TEMPWORDS"
    
    # making timestamps into millis since start
    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Converting Stamps to Millis"; fi
    while read LINE; do
        STAMP=$(sed -e "$LINE"'!d' -e "s/:/./g" "$TEMPWORDS" | cut -d"|" -f2)
        IFS=. read -a STAMP_EL <<< "$STAMP"
        MS=$(bc -l <<< "(((((${STAMP_EL[0]} * 60) + ${STAMP_EL[1]}) * 60 ) + ${STAMP_EL[2]}) * 1000 ) + ${STAMP_EL[3]}")
        sed -i "$LINE"'s/$/|'"$MS"'/' "$TEMPWORDS"
    done < <(sed -n "/|/=" "$TEMPWORDS")
    
    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Adjusting Stamps with approx word lengths"; fi
    Wc=0
    while read row; do
        IFS="|" read -a stamp <<< "$row"
        theword=$(echo $row | cut -d"|" -f 1 | sed -e "s/[^[:alpha:]]//g")
        InputMillis=${stamp[2]:="NA"}
        if grep -q --regex="^$theword$" corpus.txt; then
            WordLength=$(grep "^$theword," corpus-length.txt | cut -d, -f2)
            StartMillis=$( bc -l <<< "scale=3;$InputMillis" )
            EndMillis=$( bc -l <<< "scale=3;$InputMillis + $WordLength" )
            echo "f$(printf %06d "$Wc"),$StartMillis,$EndMillis,\"$theword\"" >> "$TEMPTIMES"
        fi
        : $(( Wc += 1 )) > /dev/null
    done < $TEMPWORDS
}

progress_update(){
    STRING="[ "
    PERCENT=$(bc -l <<< "($COUNTER / $AMOUNTOFENTRIES) * 100" | cut -d. -f1 | xargs printf %03d )
    BLOCKS=$(bc -l <<< "$COLUMNS * ($PERCENT / 100)" | cut -d. -f1)
    for block in `seq 1 $BLOCKS`; do
        STRING="${STRING}#"
    done
    for block in `seq 1 $(( COLUMNS - BLOCKS ))`; do
        STRING="${STRING} "
    done
    echo -ne "\b$STRING ] ${PERCENT:1}% ]\r" 
}

main() {
    while getopts 'o:qhrv:s:i:' flag; do
        case ${flag} in
            o) OUTPUTDIR="${OPTARG}" ;;
            h) usage ;;
            q) QUIET="true" ;;
            i) DOWNLOAD="${OPTARG}" ;;
            s) VIDEO="${OPTARG}" ;;
            v) SUBS="${OPTARG}" ;;
            r) RAM="true" ;;
            *) dusage ;;
        esac
    done
    WORKINGDIR=$(readlink -e $0 | rev | cut -d/ -f2- | rev )
    OUTPUTDIR=${OUTPUTDIR:=$WORKINGDIR/cuts}
    cd $WORKINGDIR

    TEMPDIR=$(mktemp -d ./XXXX)
    if [[ "$RAM" ]]; then
        sudo mount -t tmpfs -o size=4096m tmpfs $TEMPDIR/
    fi

    if [[ "$DOWNLOAD" ]]; then
        pushd $TEMPDIR
        youtube-dl --write-auto-sub --id --write-info-json $DOWNLOAD
        mv *.json $OUTPUTDIR/VIDEO-INFO/
        SUBS="$TEMPDIR/$DOWNLOAD.en.vtt"
        VIDEO="$TEMPDIR/$DOWNLOAD.mp4"
        popd
    fi

    STARTTIME=$(date +%s)
    TEMPWORDS=$(mktemp $TEMPDIR/XXXX)
    TEMPTIMES=$(mktemp $TEMPDIR/XXXX)
    ID=$(basename $SUBS | sed -e "s/\..*//g")

    #aenas_based_stamps
    espeak_based_stamps

    TEMPVIDEOFILE=$(mktemp --suffix=.mp4 $TEMPDIR/XXXX)
    TEMPAUDIOFILE=$(mktemp --suffix=.wav $TEMPDIR/XXXX)

    # Progress related variables 
    COLUMNS=$(bc -l <<< "$(tput cols) - 10")
    BLANK=""
    for block in `seq 1 $(( COLUMNS + 10 ))`; do 
       BLANK="${BLANK} " 
    done
    AMOUNTOFENTRIES=$(wc -l "$TEMPTIMES" | cut -d" " -f1)
    COUNTER=0
    SUCESSES=0
    FAILURES=0
    ERRORS=0
    tput cup $COLUMNS 0

    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Video Cutting"; fi
    for occurance in $(cat $TEMPTIMES); do 
        : $(( COUNTER += 1 ))
        stamp[0]=$(millis_to_stamp `cut -d, -f2 <<< "$occurance"`)
        stamp[1]=$(millis_to_stamp $(bc -l <<< "scale=0;`cut -d, -f3 <<< "$occurance"`-`cut -d, -f2 <<< "$occurance"`"))
        stamp[2]=$(cut -d, -f4 <<< "$occurance" | sed -e "s/\"//g")
    
        if grep "^${stamp[2]}$" corpus.txt -q; then
            
            CountToThree=0

            while [[ "$CountToThree" -lt "3" ]]; do
                case "$CountToThree" in
                    1) 
                        stamp[0]=$(millis_to_stamp `cut -d, -f2 <<< "$occurance"`)
                        stamp[1]=$(millis_to_stamp $(bc -l <<< "scale=0;`cut -d, -f3 <<< "$occurance"`-`cut -d, -f2 <<< "$occurance"` - 100"))
                        ;;
                    2) 
                        stamp[0]=$(millis_to_stamp $(bc -l <<< "scale=0;`cut -d, -f2 <<< "$occurance"`- 100"))
                        stamp[1]=$(millis_to_stamp $(bc -l <<< "scale=0;`cut -d, -f3 <<< "$occurance"`-`cut -d, -f2 <<< "$occurance"`"))
                        ;;
                esac
                ffmpeg -loglevel panic -ss "${stamp[0]}" -i "$VIDEO" -ss 00:00:00 -t ${stamp[1]} \
                -async 1 -c:v mpeg4 -q:v 1 -c:a aac -q:a 100 "${TEMPVIDEOFILE}" -y >/dev/null 2>&1
                ffmpeg -loglevel panic -i "${TEMPVIDEOFILE}" -vn "${TEMPAUDIOFILE}" -y >/dev/null 2>&1

                RESULT=$(./RecogniseAudio.pyo --file-name "${TEMPAUDIOFILE}")
                if [[ "$RESULT" == "${stamp[2]}" ]]; then 
                    CountToThree=4
                else
                    : $(( CountToThree += 1 ))
                fi
            done

            if [[ "$RESULT" == "${stamp[2]}" ]]; then
                : $(( SUCESSES += 1 ))
                STRING="[SUCC] Match: \"$RESULT\""
                printf '\e[1;32m%-6s\e[m' "$STRING"
                printf '%*.*s\n' 0 $((${#BLANK} - ${#STRING} )) "$BLANK"
                progress_update 2>&2
                HASH=$(sha1sum "$TEMPVIDEOFILE" | cut -d" " -f1)
                if [[ ! -d "$OUTPUTDIR/${stamp[2]}" ]]; then
                    mkdir -p "$OUTPUTDIR/${stamp[2]}"
                fi
                cp "$TEMPVIDEOFILE" "$OUTPUTDIR/${stamp[2]}/${stamp[2]}+$HASH+$ID.mp4"
            elif [[ "$RESULT" == "" ]]; then
                STRING="[ERRR] No words found in audio"
                printf '\e[1;31m%-6s\e[m' "$STRING"
                printf '%*.*s\n' 0 $((${#BLANK} - ${#STRING} )) "$BLANK"
                progress_update 2>&2
                : $(( ERRORS += 1 ))
            elif [[ "$RESULT" == "Error reading audio" ]]; then
                STRING="[ERRR] Audio probably too short: \"$occurance\""
                printf '\e[1;31m%-6s\e[m' "$STRING"
                printf '%*.*s\n' 0 $((${#BLANK} - ${#STRING} )) "$BLANK"
                progress_update 2>&2
                : $(( ERRORS += 1 ))
            else
                STRING="[FAIL] Not a Match: \"${stamp[2]}\" vs \"$RESULT\""
                printf '\e[1;30m%-6s\e[m' "$STRING" 
                printf '%*.*s\n' 0 $((${#BLANK} - ${#STRING} )) "$BLANK"
                progress_update 2>&2
                : $(( FAILURES += 1 ))
            fi
        fi
    done
    ENDTIME=$(date +%s) 
    printf '\e[1;0m%-6s\e[m' "Started: $STARTTIME "
    printf '\e[1;0m%-6s\e[m' "Took: $(( ENDTIME - STARTTIME )) "
    printf '\e[1;0m%-6s\e[m\n' "Completed:  "
    printf '\e[1;32m%-6s\e[m' "$SUCESSES Sucesses "
    printf '\e[1;31m%-6s\e[m' "$ERRORS Errors "
    printf '\e[1;30m%-6s\e[m\n' "$FAILURES Failures"

    [[ "$RAM" ]] && sudo umount $TEMPDIR
    rm -r $TEMPDIR
}
main "$@"
