#!/bin/bash
WORKINGDIR=$(dirname $0)
REALWORD=$1
READWORD=$2

OUTPUT=$($WORKINGDIR/DeMeta.pyo -w "$2" | sed -e "s/[\'\ ]//g;s/\[//;s/\]//;s/,None//")
INPUT=$(grep --regex="^$REALWORD," corpus-demeta.txt | cut -d, -f2-)

echo $OUTPUT
echo $INPUT

if [ "$INPUT" == "$OUTPUT" ]; then
    exit 0
else
    IFS=, read -a OUTPUTCODES <<< "$OUTPUT"
    IFS=, read -a INPUTCODES <<< "$INPUT"
    for code in ${OUTPUTCODES[@]}; do
        for incode in ${INPUTCODES[@]}; do
            [ "$code" == "$incode" ] && exit 0
        done
    done 
    exit 1
fi
