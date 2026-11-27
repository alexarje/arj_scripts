#!/usr/bin/env bash
# Create a dated text file and open it in your default editor.
# Usage: newfile.sh [filename]
# If no filename given, uses today's date (YYYY-MM-DD.txt).

_now=$(date -I)
_file="${_now}.txt"

[[ $# -gt 0 ]] && _file="$1"

echo "Writing new file $_file..."
touch "$_file"
${EDITOR:-nano} "$_file"
