#!/bin/bash
# TODO:
#   [*]: Fix non-auto subs
#   [*]: Temporary Corpus to adjust if a video can have multiple cuts of the same word
#   [*]: Add hardware acceleration options properly
#   [~]: More precise mode that auto adjusts a few times
#   [ ]: Implement inital load of corpus to remove terms that are already to 1000 terms
#   [ ]: Look for libraries that are needed
#   [ ]: Install script for apt systems
#   [ ]: Fix options

# Corpus values
CORPUS="corpus.txt"
CORPUSMETA="corpus-demeta.txt"
CORPUSLENGTH="corpus-length.txt"

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
    -i          youtube download with id          
EOS
exit 0
}

millis_to_stamp(){
    local seek=$(bc -l <<< "scale=0;sqrt($1^2)*1000" | cut -d. -f1)
    local millis=$(printf %03d "$(bc -l <<< "scale=0;$seek % 1000")")
    local seek=$(bc -l <<< "scale=0;($seek - $millis)/1000")
    local seconds=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    local seek=$(bc -l <<< "scale=0;($seek - $seconds)/60")
    local minutes=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    local hours=$(printf %02d "$(bc -l <<< "scale=0;($seek - $minutes)/60")")
    echo ${hours:=00}:${minutes:=00}:${seconds:=00}.${millis:=000}
}

aenas_based_stamps(){
    AENAS="true"
    echo "" > $TEMPTIMES
    
    # Clean Off Header 
    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Cleaning Subs - en or other"; fi
    tail +$( sed -n "/\-\->/=" "$SUBS" | head -1 ) "$SUBS" | sed -e "/-->/d;s/\*.*[^*]\*//g;/^$/d" -e "s/[[:space:]]/\n/g;s/</\n/g;s/'//g"| sed -e "/^\//d;/^c>/d;/:/d;/^c./d;/^$/d" >> $TEMPWORDS
    
    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Using Aeneas to realign subs"; fi
    # Uses aeneas to enforce title syncronisation
    ANOTHERTEMP=$(mktemp $TEMPDIR/XXXX)
    python -m aeneas.tools.execute_task "$VIDEO" "$TEMPWORDS" "task_language=eng|os_task_file_format=csv|is_text_type=plain" $ANOTHERTEMP

    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] When words are aligned but beginning is same as end add espeak value"; fi
    Wc=0
    while read row; do
        IFS="," read -a stamp <<< "$row"
        theword=$(echo $row | cut -d"," -f4 | sed -e "s/[^[:alpha:]]//g")
        InputMillis=${stamp[2]:="NA"}
        if [ "${stamp[1]}" == "${stamp[2]}" -o "$(bc -l <<< "scale=3;(${stamp[2]} - ${stamp[1]}) > 1")" == "1" -o "$(bc -l <<< "scale=3;(${stamp[2]} - ${stamp[1]}) < 0.1")" == "1" ]; then
            if grep -q --regex="^$theword$" $CORPUS; then
                WordLength=$(grep "^$theword," $CORPUSLENGTH | cut -d, -f2)
                StartMillis=$( bc -l <<< "scale=3;$InputMillis - ( ($WordLength/1000) / 2 )" )
                EndMillis=$( bc -l <<< "scale=3;$InputMillis + ( ($WordLength/1000) / 2 )" )
                echo "f$(printf %06d "$Wc"),0${StartMillis//-/},0${EndMillis//-/},\"$theword\"" >> "$TEMPTIMES"
            fi
        else 
            echo "$row" >> "$TEMPTIMES"
        fi
        : $(( Wc += 1 )) > /dev/null
    done < $ANOTHERTEMP

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
    done < <(sed -n "/|/=" "$TEMPWORDS" )
    
    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Adjusting Stamps with approx word lengths"; fi
    # Add the length of words to the timestamps, this is due to only getting one stamp with this method
    Wc=0
    while read row; do
        IFS="|" read -a stamp <<< "$row"
        theword=$(echo $row | cut -d"|" -f 1 | sed -e "s/[^[:alpha:]]//g")
        InputMillis=${stamp[2]:="NA"}
        if grep -q --regex="^$theword$" $CORPUS; then
            WordLength=$(grep "^$theword," $CORPUSLENGTH | cut -d, -f2)
            StartMillis=$( bc -l <<< "scale=3;($InputMillis - ( $WordLength / 2 )) /1000" )
            EndMillis=$( bc -l <<< "scale=3;($InputMillis + ( $WordLength / 2 )) /1000" )
            echo "f$(printf %06d "$Wc"),0$StartMillis,0$EndMillis,\"$theword\"" >> "$TEMPTIMES"
        fi
        : $(( Wc += 1 )) > /dev/null
    done < $TEMPWORDS
}

progress_update(){
    # Function is not portable, it will only work like this in this script
    # Draws a bar of poundsigns accross the bottom of terminal to give visual progress
    # It is bound to the amount of line done vs total lines to do of subtitle text
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

double_metaphone_czech(){
    # Reasonably portable, DeMeta.pyo is a compiled Python script that takes a word as 
    # an argument and outputs its Double Metaphone codes, this is compared then with 
    # the premade codes in the corpus-demeta.txt that should have been generated 
    # With WordEstimates.sh

    REALWORD=$1
    READWORD=$2
    
    if [ "${COMPILEDPYTHON}" == "1" ]; then
        OUTPUT=$($WORKINGDIR/DeMeta.pyo -w "$2" | sed -e "s/[\'\ ]//g;s/\[//;s/\]//;s/,None//")
    else
        OUTPUT=$(python $WORKINGDIR/DeMeta.py -w "$2" | sed -e "s/[\'\ ]//g;s/\[//;s/\]//;s/,None//")
    fi
    INPUT=$(grep --regex="^$REALWORD," $CORPUSMETA | cut -d, -f2-)

    [ "$AENAS" == "true" ] && return 1
    
    if [ "$INPUT" == "$OUTPUT" ]; then
        return 0
    else
        IFS=, read -a OUTPUTCODES <<< "$OUTPUT"
        IFS=, read -a INPUTCODES <<< "$INPUT"
        for code in ${OUTPUTCODES[@]}; do
            for incode in ${INPUTCODES[@]}; do
                [ "$code" == "$incode" ] && return 0
            done
        done 
        return 1
    fi
}

main() {
    while getopts 'a:o:qhrv:s:i:p' flag; do
        case ${flag} in
            o) OUTPUTDIR="${OPTARG}" ;;
            h) usage ;;
            q) QUIET="true" ;;
            i) DOWNLOAD="${OPTARG}" ;;
            s) VIDEO="${OPTARG}" ;;
            v) SUBS="${OPTARG}" ;;
            r) RAM="true" ;;
            a) ACCELERATOR="${OPTARG}" ;;
            p) COMPILEDPYTHON="1" ;;
            *) dusage ;;
        esac
    done
    # Get the fullpath of the directory the script is in and set workingdir to it
    # output is cuts by default but can be changed with an option

    WORKINGDIR=$(readlink -e $0 | rev | cut -d/ -f2- | rev )
    OUTPUTDIR=${OUTPUTDIR:=$WORKINGDIR/cuts}
    cd $WORKINGDIR

    # Here is where the creation of a new temporary corpus text should be made
    # This will get better speed as more videos are added to the database 


    # This next part will likely make the script only work on linux, this is to
    # help with avoiding wearing out a drive it is an option so that things can 
    # be tested or used without root

    TEMPDIR=$(mktemp -d ./XXXX)
    if [[ "$RAM" ]]; then
        sudo mount -t tmpfs -o size=4096m tmpfs $TEMPDIR/
    fi


    # The download option is the recommended, the subs of any site should work when script is done
    if [[ "$DOWNLOAD" ]]; then
        pushd $TEMPDIR
        # Some youtube ID's begin with -, this isnt fun
        CUTBACK=$(echo "$DOWNLOAD" | sed -e "s/[a-zA-Z0-9\_\-]//g")
        if [ $CUTBACK ]; then
            youtube-dl --write-auto-sub -f bestvideo[ext=mp4]+bestaudio[ext=m4a] --id --write-info-json '${DOWNLOAD}'
        else
            youtube-dl --write-auto-sub -f bestvideo[ext=mp4]+bestaudio[ext=m4a] --id --write-info-json "https://youtube.com/watch?v=${DOWNLOAD}"
        fi
        mv *.json $OUTPUTDIR/VIDEO-INFO/
        # This will only work for english right now 
        SUBS="$TEMPDIR/$DOWNLOAD.en.vtt"
        # The video variable should really be adjusted to find the matching videos for the subs 
        VIDEO="$TEMPDIR/$DOWNLOAD.mp4"
        popd
    fi

    STARTTIME=$(date +%s)
    TEMPWORDS=$(mktemp $TEMPDIR/XXXX)
    TEMPTIMES=$(mktemp $TEMPDIR/XXXX)
    ID=$(basename $SUBS | sed -e "s/\..*//g")
    AENAS="false"


    # If the subs adjust colour they are usually auto-generated, this works well-enough
    if grep "::cue" $SUBS -q; then
       espeak_based_stamps
    else
       aenas_based_stamps
    fi

    TEMPVIDEOFILE=$(mktemp --suffix=.mp4 $TEMPDIR/XXXX)
    TEMPAUDIOFILE=$(mktemp --suffix=.wav $TEMPDIR/XXXX)

    # Make a temporary Corpus so that we can adjust which words to keep later
    TEMPCORPUS=$(mktemp --suffix=.txt $TEMPDIR/XXXX)
    cp $CORPUS $TEMPCORPUS

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
    
        if grep "^${stamp[2]}$" $TEMPCORPUS -q; then
            
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
                ffmpeg -threads 4 -ss "${stamp[0]}" -i "$VIDEO" -ss 00:00:00 -t ${stamp[1]} \
                -async 1 -c:v mpeg4 -q:v 1 -c:a aac -q:a 100 "${TEMPVIDEOFILE}" -y >/dev/null 2>&1
                ffmpeg -threads 4 -i "${TEMPVIDEOFILE}" -vn "${TEMPAUDIOFILE}" -y >/dev/null 2>&1

                if [ "${COMPILEDPYTHON}" == "1" ]; then
                    RESULT=$(./RecogniseAudio.pyo --file-name "${TEMPAUDIOFILE}")
                else
                    RESULT=$(python ./RecogniseAudio.py --file-name "${TEMPAUDIOFILE}")
                fi
                if [[ "$RESULT" == "${stamp[2]}" ]]; then 
                    CountToThree=4
                else
                    CountToThree=4
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
                sed -i -e "/^${stamp[2]}$/d" $TEMPCORPUS
                cp "$TEMPVIDEOFILE" "$OUTPUTDIR/${stamp[2]}/${stamp[2]}+$HASH+$ID.mp4"
            elif [[ "$RESULT" == "" ]]; then
                STRING="[ERRO] No words found in audio"
                printf '\e[1;31m%-6s\e[m' "$STRING"
                printf '%*.*s\n' 0 $((${#BLANK} - ${#STRING} )) "$BLANK"
                progress_update 2>&2
                : $(( ERRORS += 1 ))
            elif [[ "$RESULT" == "Error reading audio" ]]; then
                STRING="[ERRO] Audio probably too short: \"$occurance\""
                printf '\e[1;31m%-6s\e[m' "$STRING"
                printf '%*.*s\n' 0 $((${#BLANK} - ${#STRING} )) "$BLANK"
                progress_update 2>&2
                : $(( ERRORS += 1 ))
            else
                if double_metaphone_czech "${stamp[2]}" "$RESULT"; then
                    STRING="[SUCC] Maybe Match: \"${stamp[2]}\" vs \"$RESULT\""
                    printf '\e[1;32m%-6s\e[m' "$STRING" 
                    printf '%*.*s\n' 0 $((${#BLANK} - ${#STRING} )) "$BLANK"
                    progress_update 2>&2
                    : $(( SUCESSES += 1 ))
                    HASH=$(sha1sum "$TEMPVIDEOFILE" | cut -d" " -f1)
                    if [[ ! -d "$OUTPUTDIR/${stamp[2]}" ]]; then
                        mkdir -p "$OUTPUTDIR/${stamp[2]}"
                    fi
                    sed -i -e "/^${stamp[2]}$/d" $TEMPCORPUS
                    cp "$TEMPVIDEOFILE" "$OUTPUTDIR/${stamp[2]}/${stamp[2]}+$HASH+$ID.mp4"
                else
                    STRING="[FAIL] Not a Match: \"${stamp[2]}\" vs \"$RESULT\""
                    printf '\e[1;30m%-6s\e[m' "$STRING" 
                    printf '%*.*s\n' 0 $((${#BLANK} - ${#STRING} )) "$BLANK"
                    progress_update 2>&2
                    : $(( FAILURES += 1 ))
                fi
            fi
        fi
    done
    ENDTIME=$(date +%s) 
    printf '\e[1;0m%-6s\e[m' "Started: $STARTTIME "
    printf '\e[1;0m%-6s\e[m' "Took: $(( ENDTIME - STARTTIME )) "
    printf '\e[1;0m%-6s\e[m\n' "Completed: $ENDTIME "
    printf '\e[1;32m%-6s\e[m' "$SUCESSES Sucesses "
    printf '\e[1;31m%-6s\e[m' "$ERRORS Errors "
    printf '\e[1;30m%-6s\e[m\n' "$FAILURES Failures"

    [[ "$RAM" ]] && sudo umount $TEMPDIR
    rm -r $TEMPDIR
}
main "$@"
