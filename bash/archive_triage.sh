#!/usr/bin/env bash
# Report "cold" files on an archive drive - files not modified in N days - so
# they can be moved to cold storage. Shows the total, a per-folder breakdown,
# and the largest cold files; optionally moves everything cold into a staging
# folder, preserving relative paths. Uses modification time (mtime), since
# access times are unreliable on modern mounts (relatime/noatime).
# Usage: archive_triage.sh [options] <folder>
#   --days N     age threshold in days (default 1825 = 5 years)
#   --top N      how many of the largest cold files to list (default 20)
#   --move DEST  move cold files to DEST/<relative path> (asks for confirmation)
#   --yes        skip the confirmation prompt when moving
# Default is report-only. Moves never overwrite existing files and are logged
# to archive_triage_<timestamp>.log in the current dir.

set -euo pipefail

days=1825
top=20
dest=""
assume_yes=0
root=""

usage() {
  echo "Usage: archive_triage.sh [--days N] [--top N] [--move DEST] [--yes] <folder>" >&2
}

while (( $# )); do
  case "$1" in
    --days) shift; days="${1:?--days needs a number}" ;;
    --top) shift; top="${1:?--top needs a number}" ;;
    --move) shift; dest="${1:?--move needs a destination}" ;;
    --yes) assume_yes=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *) root="$1" ;;
  esac
  shift
done

[[ -n $root ]] || { usage; exit 1; }
[[ -d $root ]] || { echo "Not a directory: $root" >&2; exit 1; }
root="${root%/}"

if [[ -n $dest ]]; then
  # Refuse a destination inside the scanned tree: moved files would pile up
  # as new "cold" content on the very drive being cleaned.
  case "$(readlink -f -- "$dest")/" in
    "$(readlink -f -- "$root")"/*) echo "Destination must be outside $root" >&2; exit 1 ;;
  esac
fi

human() { numfmt --to=iec --suffix=B "${1:-0}"; }

echo "Scanning: $root for files unmodified in the last $days days (this can take a while)"

# Stream the scan: cold files come out prefixed "M<TAB><size><TAB><path>";
# every directory emits a bare "S" tick so the counter keeps moving.
entries=()
scanned=0
scan_progress() {
  printf '\r\033[K  %d folder(s) scanned, %d cold file(s) found' \
    "$scanned" "${#entries[@]}" >&2
}
while IFS= read -r -d '' rec; do
  if [[ $rec == M$'\t'* ]]; then
    entries+=("${rec#M$'\t'}")
    (( ${#entries[@]} % 100 == 0 )) && scan_progress
  else
    (( ++scanned % 100 == 0 )) && scan_progress
  fi
done < <(find "$root" \
  \( -type f -mtime +"$days" -printf 'M\t%s\t%p\0' \) -o \
  \( -type d -printf 'S\0' \) \
  2>/dev/null || true)
scan_progress
echo >&2

if (( ${#entries[@]} == 0 )); then
  echo "No files older than $days days under: $root"
  exit 0
fi

# Break the cold bytes down by top-level folder under the scan root.
declare -A dir_bytes=() dir_count=()
total_bytes=0
for e in "${entries[@]}"; do
  sz="${e%%$'\t'*}"
  p="${e#*$'\t'}"
  rel="${p#"$root"/}"
  topdir="${rel%%/*}"
  [[ $topdir == "$rel" ]] && topdir="."
  dir_bytes[$topdir]=$(( ${dir_bytes[$topdir]:-0} + sz ))
  dir_count[$topdir]=$(( ${dir_count[$topdir]:-0} + 1 ))
  total_bytes=$(( total_bytes + sz ))
done

echo
echo "Cold data by folder (largest first):"
for d in "${!dir_bytes[@]}"; do
  printf '%s\t%s\t%s\n' "${dir_bytes[$d]}" "$d" "${dir_count[$d]}"
done | sort -rn | while IFS=$'\t' read -r bytes d count; do
  printf '  %8s  %6d file(s)  %s/\n' "$(human "$bytes")" "$count" "$d"
done

echo
echo "Largest cold files:"
printf '%s\0' "${entries[@]}" | sort -z -t $'\t' -k1,1nr | head -z -n "$top" \
  | while IFS=$'\t' read -r -d '' sz p; do
      printf '  %8s  %s\n' "$(human "$sz")" "$p"
    done

echo
echo "Total: ${#entries[@]} cold file(s), $(human "$total_bytes") (unmodified for $days+ days)."

if [[ -z $dest ]]; then
  echo "Report only - nothing was moved. Re-run with --move DEST to relocate these."
  exit 0
fi

if (( ! assume_yes )); then
  read -r -p "Move ${#entries[@]} file(s) ($(human "$total_bytes")) to $dest? Type 'yes' to confirm: " answer
  [[ $answer == yes ]] || { echo "Aborted - nothing moved."; exit 1; }
fi

log="archive_triage_$(date +%Y%m%d_%H%M%S).log"
moved=0
failed=0
for i in "${!entries[@]}"; do
  printf '\r\033[K  Moving %d/%d' "$(( i + 1 ))" "${#entries[@]}" >&2
  p="${entries[$i]#*$'\t'}"
  rel="${p#"$root"/}"
  target="$dest/$rel"
  if [[ -e $target ]]; then
    (( ++failed ))
    printf '\r\033[K' >&2
    echo "  Skipped (already exists at destination): $p" >&2
    continue
  fi
  if mkdir -p -- "$(dirname -- "$target")" && mv -n -- "$p" "$target" 2>/dev/null; then
    (( ++moved ))
    printf '%s\t->\t%s\n' "$p" "$target" >> "$log"
  else
    (( ++failed ))
    printf '\r\033[K' >&2
    echo "  Failed to move: $p" >&2
  fi
done
printf '\r\033[K' >&2

echo "Moved $moved file(s) (about $(human "$total_bytes")) to $dest. Log: $log"
(( failed > 0 )) && echo "Skipped/failed $failed file(s) - see messages above." >&2
echo "Tip: empty folders may remain; remove them with: find \"$root\" -type d -empty -delete"
exit 0
