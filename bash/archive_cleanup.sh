#!/usr/bin/env bash
# Scan an archive drive/folder for useless system files and optionally delete them:
#   junk    - OS metadata: .DS_Store, ._* (AppleDouble), Thumbs.db, desktop.ini,
#             .Spotlight-V100, .fseventsd, .TemporaryItems, .Trashes, .Trash-*, .apdisk
#   dropbox - Dropbox leftovers: .dropbox, .dropbox.attr, .dropbox.cache
#   tmp     - temp/backup files: *.tmp, *.temp, *~, *.swp, ~$* (Office temp)
# Only these known-useless names are ever touched; your own data is never matched.
# Usage: archive_cleanup.sh [options] <folder>
#   --delete       actually delete matches (default is a dry run that only reports)
#   --yes          skip the confirmation prompt when deleting
#   --skip CAT     skip a category (repeatable)
#   --only CAT     run only the given category (repeatable)
#   --quiet        only print the per-category summary, not every match
# Deletions are logged to archive_cleanup_<timestamp>.log in the current dir.

set -euo pipefail

categories=(junk dropbox tmp)

usage() {
  echo "Usage: archive_cleanup.sh [--delete] [--yes] [--quiet] [--skip CAT] [--only CAT] <folder>" >&2
  echo "Categories: ${categories[*]}" >&2
}

do_delete=0
assume_yes=0
quiet=0
root=""
declare -A enabled=()
for c in "${categories[@]}"; do enabled[$c]=1; done
only_used=0

valid_cat() {
  local c
  for c in "${categories[@]}"; do [[ $c == "$1" ]] && return 0; done
  echo "Unknown category: $1 (valid: ${categories[*]})" >&2
  exit 1
}

while (( $# )); do
  case "$1" in
    --delete) do_delete=1 ;;
    --yes) assume_yes=1 ;;
    --quiet) quiet=1 ;;
    --skip) shift; valid_cat "${1:-}"; enabled[$1]=0 ;;
    --only)
      shift; valid_cat "${1:-}"
      if (( ! only_used )); then
        for c in "${categories[@]}"; do enabled[$c]=0; done
        only_used=1
      fi
      enabled[$1]=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *) root="$1" ;;
  esac
  shift
done

[[ -n $root ]] || { usage; exit 1; }
[[ -d $root ]] || { echo "Not a directory: $root" >&2; exit 1; }

echo "Scanning: $root (this can take a while on a large drive)"

# One pass over the drive. Matched directories are pruned so we never descend
# into (or double-count) anything already slated for removal.
mapfile -d '' -t matches < <(find "$root" \
  \( -type d \( -name .Spotlight-V100 -o -name .fseventsd -o -name .TemporaryItems \
     -o -name .Trashes -o -name '.Trash-*' -o -name .dropbox.cache \) -prune -print0 \) -o \
  \( -type f \( -name .DS_Store -o -name '._*' -o -name Thumbs.db -o -name desktop.ini \
     -o -name .apdisk -o -name .dropbox -o -name .dropbox.attr \
     -o -name '*.tmp' -o -name '*.temp' -o -name '*~' -o -name '*.swp' -o -name '~$*' \) \
     -print0 \) \
  2>/dev/null || true)

category_of() {
  case "$(basename -- "$1")" in
    .dropbox.cache|.dropbox|.dropbox.attr) echo dropbox ;;
    .DS_Store|._*|Thumbs.db|desktop.ini|.apdisk|.Spotlight-V100|.fseventsd|.TemporaryItems|.Trashes|.Trash-*) echo junk ;;
    *.tmp|*.temp|*~|*.swp|'~$'*) echo tmp ;;
    *) echo "" ;;
  esac
}

# Sort matches into per-category lists, honoring --skip/--only.
declare -A cat_count=() cat_bytes=()
targets=()          # everything that will be reported/deleted
target_cats=()      # parallel array: category per target
for p in "${matches[@]}"; do
  cat=$(category_of "$p")
  [[ -n $cat && ${enabled[$cat]} -eq 1 ]] || continue
  targets+=("$p")
  target_cats+=("$cat")
done

if (( ${#targets[@]} == 0 )); then
  echo "Nothing to clean up under: $root"
  exit 0
fi

# Measure sizes in one du call (bytes), then report per match and per category.
echo "Measuring sizes of ${#targets[@]} match(es)..."
mapfile -t sizes < <(printf '%s\0' "${targets[@]}" | du -sb --files0-from=- 2>/dev/null | cut -f1)

human() { numfmt --to=iec --suffix=B "${1:-0}"; }

total_bytes=0
for i in "${!targets[@]}"; do
  sz="${sizes[$i]:-0}"
  cat="${target_cats[$i]}"
  cat_count[$cat]=$(( ${cat_count[$cat]:-0} + 1 ))
  cat_bytes[$cat]=$(( ${cat_bytes[$cat]:-0} + sz ))
  total_bytes=$(( total_bytes + sz ))
  (( quiet )) || printf '  [%s] %8s  %s\n' "$cat" "$(human "$sz")" "${targets[$i]}"
done

echo
echo "Summary:"
for c in "${categories[@]}"; do
  (( ${cat_count[$c]:-0} > 0 )) || continue
  printf '  %-8s %6d item(s)  %8s\n' "$c" "${cat_count[$c]}" "$(human "${cat_bytes[$c]}")"
done
printf '  %-8s %6d item(s)  %8s\n' "TOTAL" "${#targets[@]}" "$(human "$total_bytes")"

if (( ! do_delete )); then
  echo
  echo "Dry run only - nothing was deleted. Re-run with --delete to remove these."
  exit 0
fi

if (( ! assume_yes )); then
  echo
  read -r -p "Delete all ${#targets[@]} item(s) listed above? Type 'yes' to confirm: " answer
  [[ $answer == yes ]] || { echo "Aborted - nothing deleted."; exit 1; }
fi

log="archive_cleanup_$(date +%Y%m%d_%H%M%S).log"
deleted=0
failed=0
for i in "${!targets[@]}"; do
  p="${targets[$i]}"
  if rm -rf -- "$p" 2>/dev/null; then
    (( ++deleted ))
    printf '[%s] %s\n' "${target_cats[$i]}" "$p" >> "$log"
  else
    # Read-only permission bits can block directory removal; loosen and retry once.
    chmod -R u+rwX -- "$p" 2>/dev/null || true
    if rm -rf -- "$p" 2>/dev/null; then
      (( ++deleted ))
      printf '[%s] %s\n' "${target_cats[$i]}" "$p" >> "$log"
    else
      (( ++failed ))
      echo "  Failed to delete: $p" >&2
    fi
  fi
done

echo
echo "Deleted $deleted item(s), freed about $(human "$total_bytes"). Log: $log"
(( failed > 0 )) && echo "Failed to delete $failed item(s) - see messages above." >&2
exit 0
