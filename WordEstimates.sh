#!/bin/bash
WORKINGDIR=$(dirname $0)
pushd $WORKINGDIR
if [ ! -e corpus.txt ]; then
    wget -O corpus.txt https://raw.githubusercontent.com/first20hours/google-10000-english/master/google-10000-english.txt
fi
TEMPSOUND=$(mktemp)
if [ ! -e corpus-length.txt ]; then
    while read line; do
        espeak -s 150 -w $TEMPSOUND "$line"
        DURATION=$(($(mediainfo --Inform="Audio;%Duration%" $TEMPSOUND) - 400))
        if [ -e corpus-length.txt ]; then 
            if grep "$line" corpus-length.txt; then
                DoesExist=0
                while read entry; do 
                    if [ "$entry" == "$line" ]; then 
                        : $(( DoesExist += 1 ))
                    fi
                done < <(grep "$line" corpus-length.txt | cut -d, -f1)
                if [ "$DoesExist" == "0" ]; then
                    echo $line,$DURATION >> corpus-length.txt
                fi
            else
                echo $line,$DURATION >> corpus-length.txt
            fi
    
        else 
            echo $line,$DURATION >> corpus-length.txt
        fi
    done < corpus.txt
fi

if [ ! -e corpus-demeta.txt ]; then
    while read word; do 
        OUT=$(python ./DeMeta.py -w "$word" | sed -e "s/[\'\ ]//g;s/\[//;s/\]//;s/,None//")
        echo "$word,$OUT" >> corpus-demeta.txt
    done < corpus.txt
fi

popd
