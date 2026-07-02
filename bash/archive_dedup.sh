#!/usr/bin/env bash
# Find byte-identical duplicate files on an archive drive and report the wasted
# space. Detection runs in three cheap-to-expensive stages: same size -> same
# first 1 MiB (sha256) -> same full sha256. Files that are already hardlinks of
# each other are not counted as waste. The kept copy in each group is the
# oldest file (ties broken alphabetically).
# Usage: archive_dedup.sh [options] <folder>
#   --min-size SIZE   ignore files smaller than this (default 1M, find(1) syntax)
#   --hardlink        replace each duplicate with a hardlink to the kept copy
#   --delete          delete duplicates, keeping one copy per group
#   --yes             skip the confirmation prompt
# Default is report-only; nothing is changed without --hardlink or --delete.
# Actions are logged to archive_dedup_<timestamp>.log in the current dir.

set -euo pipefail

min_size="1M"
action="report"
assume_yes=0
root=""

usage() {
  echo "Usage: archive_dedup.sh [--min-size 1M] [--hardlink|--delete] [--yes] <folder>" >&2
}

while (( $# )); do
  case "$1" in
    --min-size) shift; min_size="${1:?--min-size needs a value}" ;;
    --hardlink) action="hardlink" ;;
    --delete) action="delete" ;;
    --yes) assume_yes=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *) root="$1" ;;
  esac
  shift
done

[[ -n $root ]] || { usage; exit 1; }
[[ -d $root ]] || { echo "Not a directory: $root" >&2; exit 1; }

human() { numfmt --to=iec --suffix=B "${1:-0}"; }

echo "Scanning: $root for files larger than $min_size (this can take a while)"

# Stream the scan: candidate files come out prefixed "M<TAB>size<TAB>dev:inode
# <TAB>mtime<TAB>path"; every directory emits a bare "S" tick for the counter.
entries=()
scanned=0
scan_progress() {
  printf '\r\033[K  %d folder(s) scanned, %d file(s) collected' \
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
  \( -type f -size +"$min_size" -printf 'M\t%s\t%D:%i\t%T@\t%p\0' \) -o \
  \( -type d -printf 'S\0' \) \
  2>/dev/null || true)
scan_progress
echo >&2

if (( ${#entries[@]} < 2 )); then
  echo "Not enough files to compare under: $root"
  exit 0
fi

# Sort by size (then age, then path) so same-size candidates are adjacent and
# the oldest file naturally comes first within each eventual duplicate group.
mapfile -d '' -t entries < <(printf '%s\0' "${entries[@]}" \
  | sort -z -t $'\t' -k1,1n -k3,3n -k4)

sizes=(); mtimes=(); paths=()
declare -A seen_inode=()
for e in "${entries[@]}"; do
  IFS=$'\t' read -r sz ino mt p <<<"$e"
  # Extra paths of an already-seen inode are the same physical file; skip them.
  [[ -n ${seen_inode[$ino]:-} ]] && continue
  seen_inode[$ino]=1
  sizes+=("$sz"); mtimes+=("$mt"); paths+=("$p")
done
n=${#paths[@]}

# Stage 1: indices of files whose size is shared by at least one other file.
candidates=()
for (( i = 0; i < n; i++ )); do
  if (( i > 0 )) && [[ ${sizes[$i]} == "${sizes[$((i-1))]}" ]]; then
    [[ ${#candidates[@]} -gt 0 && ${candidates[-1]} == "$((i-1))" ]] || candidates+=("$((i-1))")
    candidates+=("$i")
  fi
done

if (( ${#candidates[@]} == 0 )); then
  echo "No duplicate candidates (no two files share a size). Nothing to do."
  exit 0
fi
echo "${#candidates[@]} of $n file(s) share a size with another file; hashing those..."

# Stage 2+3: group candidates by size + first-MiB hash, then confirm groups
# with a full-file hash. Files of 1 MiB or less skip the full hash (the
# partial hash already covers the whole file).
declare -A groups=()   # "size:fullhash" -> space-separated indices
hashed=0
for i in "${candidates[@]}"; do
  p="${paths[$i]}"
  printf '\r\033[K  hashing %d/%d: %s' "$(( ++hashed ))" "${#candidates[@]}" \
    "$(basename -- "$p")" >&2
  phash=$(head -c 1048576 -- "$p" 2>/dev/null | sha256sum | cut -d' ' -f1) || continue
  groups["p:${sizes[$i]}:$phash"]+=" $i"
done
printf '\r\033[K' >&2

declare -A final=()    # confirmed duplicate groups
fulln=0
for key in "${!groups[@]}"; do
  read -ra idxs <<<"${groups[$key]}"
  (( ${#idxs[@]} > 1 )) || continue
  if (( ${sizes[${idxs[0]}]} <= 1048576 )); then
    final[$key]="${groups[$key]}"
    continue
  fi
  for i in "${idxs[@]}"; do
    printf '\r\033[K  full-hashing large candidate %d: %s' "$(( ++fulln ))" \
      "$(basename -- "${paths[$i]}")" >&2
    fhash=$(sha256sum -- "${paths[$i]}" 2>/dev/null | cut -d' ' -f1) || continue
    final["f:${sizes[$i]}:$fhash"]+=" $i"
  done
done
printf '\r\033[K' >&2

# Report groups sorted by wasted bytes, largest first.
report=()
total_wasted=0
dup_count=0
for key in "${!final[@]}"; do
  read -ra idxs <<<"${final[$key]}"
  (( ${#idxs[@]} > 1 )) || continue
  wasted=$(( ${sizes[${idxs[0]}]} * (${#idxs[@]} - 1) ))
  total_wasted=$(( total_wasted + wasted ))
  dup_count=$(( dup_count + ${#idxs[@]} - 1 ))
  report+=("$wasted $key")
done

if (( ${#report[@]} == 0 )); then
  echo "No duplicates found under: $root"
  exit 0
fi

echo
keepers=(); dups=()
while read -r wasted key; do
  read -ra idxs <<<"${final[$key]}"
  echo "Group: ${#idxs[@]} copies x $(human "${sizes[${idxs[0]}]}")  ($(human "$wasted") wasted)"
  first=1
  for i in "${idxs[@]}"; do
    if (( first )); then
      printf '  keep  %s\n' "${paths[$i]}"
      first=0
    else
      printf '  dup   %s\n' "${paths[$i]}"
      keepers+=("${paths[${idxs[0]}]}")
      dups+=("${paths[$i]}")
    fi
  done
done < <(printf '%s\n' "${report[@]}" | sort -rn)

echo
echo "Found $dup_count duplicate file(s) in ${#report[@]} group(s), $(human "$total_wasted") reclaimable."

if [[ $action == report ]]; then
  echo "Report only - nothing was changed. Re-run with --hardlink or --delete."
  exit 0
fi

if (( ! assume_yes )); then
  read -r -p "${action^} $dup_count duplicate(s) listed above? Type 'yes' to confirm: " answer
  [[ $answer == yes ]] || { echo "Aborted - nothing changed."; exit 1; }
fi

log="archive_dedup_$(date +%Y%m%d_%H%M%S).log"
done_n=0
failed=0
for i in "${!dups[@]}"; do
  printf '\r\033[K  %s %d/%d' "${action}ing" "$(( i + 1 ))" "${#dups[@]}" >&2
  keep="${keepers[$i]}"; dup="${dups[$i]}"
  [[ -f $keep ]] || { (( ++failed )); continue; }
  ok=0
  if [[ $action == hardlink ]]; then
    ln -f -- "$keep" "$dup" 2>/dev/null && ok=1
  else
    rm -f -- "$dup" 2>/dev/null && ok=1
  fi
  if (( ok )); then
    (( ++done_n ))
    printf '%s\t%s\t(kept: %s)\n' "${action^^}" "$dup" "$keep" >> "$log"
  else
    (( ++failed ))
    printf '\r\033[K' >&2
    echo "  Failed to $action: $dup" >&2
  fi
done
printf '\r\033[K' >&2

echo "${action^}ed $done_n duplicate(s), reclaimed about $(human "$total_wasted"). Log: $log"
(( failed > 0 )) && echo "Failed on $failed file(s) - see messages above." >&2
exit 0
