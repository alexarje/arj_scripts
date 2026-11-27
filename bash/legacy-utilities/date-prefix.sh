#!/usr/bin/env bash
# Prefix filenames with a date stamp.
# Replaces: add_date, add-date.sh, add_today.py
#
# Usage:
#   date-prefix.sh [-f FORMAT] FILE...
#   date-prefix.sh [-f FORMAT] -d DIRECTORY [-e EXTENSION]
#
# Options:
#   -f FORMAT    strftime format (default: %Y-%m-%d)
#   -d DIRECTORY process all files in directory
#   -e EXTENSION filter by extension (e.g. '*.md', '*.txt')
#   -h           show this help
#
# Examples:
#   date-prefix.sh draft.md                    → 2026-11-27-draft.md
#   date-prefix.sh -f %y_%m_%d draft.md        → 26_11_27-draft.md
#   date-prefix.sh -f %Y%m%d_ -d . -e '*.txt'  → prefix all .txt files

set -euo pipefail

format="%Y-%m-%d"
directory=""
extension="*"

usage() {
    sed -n '2,19p' "$0" | sed 's/^# //'
    exit 1
}

while getopts "f:d:e:h" opt; do
    case $opt in
        f) format="$OPTARG" ;;
        d) directory="$OPTARG" ;;
        e) extension="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

prefix=$(date +"$format")

if [[ -n "$directory" ]]; then
    if [[ ! -d "$directory" ]]; then
        echo "Error: '$directory' is not a directory" >&2
        exit 1
    fi
    cd "$directory"
    for f in $extension; do
        [[ -e "$f" ]] || continue
        newname="${prefix}${f}"
        [[ "$f" == "$newname" ]] && continue
        mv -n "$f" "$newname"
        echo "Renamed: $f → $newname"
    done
else
    if [[ $# -eq 0 ]]; then
        usage
    fi
    for f in "$@"; do
        if [[ ! -e "$f" ]]; then
            echo "Error: '$f' not found" >&2
            continue
        fi
        newname="${prefix}$(basename "$f")"
        [[ "$f" == "$newname" ]] && continue
        mv -n "$f" "$newname"
        echo "Renamed: $f → $newname"
    done
fi
