while read entry; do ./Process.sh -i $entry -p -o rogers && sed -i -e "/^${entry}$/d" 100IDS; done < <(cat 100IDS)
