while read entry; do ./Process.sh -r -i $entry && sed -i -e "/^${entry}$/d" 100IDS; done < <(cat 100IDS)
