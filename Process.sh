#!/bin/bash
# TODO:
#   [*]: Move all processing to RAM to help prevent needless disk wear
#   [*]: More options & finetuning
#   [*]: Modularise code into functions more & move to more native bash functions
#   [ ]: JSON info file for every downloaded video
#   [ ]: More precise mode that auto adjusts a few times
#   [ ]: Automatically ignore videos that will probably be too short
#   [ ]: Look for libraries that are needed
#   [ ]: Install script for apt systems
#   [ ]: A damn status bar so I dont have to do maths in my head

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
    local seek="${1/./}"
    local millis=$(printf %03d "$(bc -l <<< "scale=0;$seek % 1000")")
    local seek=$(bc -l <<< "scale=0;($seek - $millis)/1000")
    local seconds=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    local seek=$(bc -l <<< "scale=0;($seek - $seconds)/60")
    local minutes=$(printf %02d "$(bc -l <<< "scale=0;$seek % 60")")
    local hours=$(printf %02d "$(bc -l <<< "scale=0;($seek - $minutes)/60")")
    echo ${hours:=00}:${minutes:=00}:${seconds:=00}.${millis:=000}
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
    WORKINGDIR=$(dirname $0)
    cd $WORKINGDIR

    TEMPDIR=$(mktemp -d ./XXXX)
    if [[ "$RAM" ]]; then
        sudo mount -t tmpfs -o size=4096m tmpfs $TEMPDIR/
    fi

    if [[ "$DOWNLOAD" ]]; then
        pushd $TEMPDIR
        youtube-dl --write-auto-sub --id $DOWNLOAD
        SUBS="$TEMPDIR/$DOWNLOAD.en.vtt"
        VIDEO="$TEMPDIR/$DOWNLOAD.mp4"
        popd
    fi
    
    STARTTIME=$(date +%S)
    TEMPWORDS=$(mktemp $TEMPDIR/XXXX)
    TEMPTIMES=$(mktemp $TEMPDIR/XXXX)

    ID=$(basename $SUBS | sed -e "s/\..*//g")

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
    
    SUCESSES=0
    FAILURES=0
    ERRORS=0
    TEMPVIDEOFILE=$(mktemp --suffix=.mp4 $TEMPDIR/XXXX)
    TEMPAUDIOFILE=$(mktemp --suffix=.wav $TEMPDIR/XXXX)
    if [ ! $QUIET ]; then printf '\e[1;34m%-6s\e[m\n' "[INFO] Video Cutting"; fi
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
                : $(( SUCESSES += 1 ))
                printf '\e[1;32m%-6s\e[m\n' "[SUCC] Match: \"$RESULT\""
                HASH=$(sha1sum "$TEMPVIDEOFILE" | cut -d" " -f1)
                cp "$TEMPVIDEOFILE" "cuts/${stamp[2]}+$HASH+$ID.mp4"
            elif [[ "$RESULT" == "" ]]; then
                printf '\e[1;31m%-6s\e[m\n' "[ERRR] No words found in audio"
                : $(( ERRORS += 1 ))
            elif [[ "$RESULT" == "Error reading audio" ]]; then
                printf '\e[1;31m%-6s\e[m\n' "[ERRR] Audio probably too short: \"$occurance\""
                : $(( ERRORS += 1 ))
            else
                printf '\e[1;30m%-6s\e[m\n' "[FAIL] Not a Match: \"${stamp[2]}\" vs \"$RESULT\""
                : $(( FAILURES += 1 ))
            fi
        fi
    done
    
    printf '\e[1;0m%-6s\e[m' "Started: $STARTTIME "
    printf '\e[1;0m%-6s\e[m\n' "Completed: $(date +%S) "
    printf '\e[1;32m%-6s\e[m' "$SUCESSES Sucesses "
    printf '\e[1;31m%-6s\e[m' "$ERRORS Errors "
    printf '\e[1;30m%-6s\e[m\n' "$FAILURES Failures"

    [[ "$RAM" ]] && sudo umount $TEMPDIR
    rm -r $TEMPDIR
}
main "$@"
