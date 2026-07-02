#!/usr/bin/env bash
# Verify that each .avi has a matching, fully-converted .mp4 next to it, and
# delete the original .avi only when their metadata matches.
#
# Pairs are matched by name: <name>.avi  <->  <name>.mp4  (same folder).
# "Matches" means: same video width/height AND durations within tolerance.
# The duration check is what catches interrupted/partial conversions (e.g. a
# 500s source that only produced a 68s mp4) so those originals are kept.
#
# SAFE BY DEFAULT: this only previews (dry-run). Add --delete to actually remove.
#
# Usage:
#   avi2mp4_cleanup.sh [folder] [--delete] [--tolerance SECONDS] [--pct PCT]
#     folder            directory to scan recursively (default: current dir)
#     --delete          actually delete matching .avi files (default: dry-run)
#     --tolerance SEC   allowed absolute duration diff in seconds (default: 1.0)
#     --pct PCT         allowed duration diff as percent of avi length (default: 1.0)
#   A pair matches if the duration diff is within EITHER the SEC or PCT bound.

set -euo pipefail

root="."
do_delete=0
tol_sec="1.0"
tol_pct="1.0"

while (( $# )); do
  case "$1" in
    --delete)      do_delete=1; shift ;;
    --tolerance)   tol_sec="${2:?--tolerance needs a value}"; shift 2 ;;
    --pct)         tol_pct="${2:?--pct needs a value}"; shift 2 ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            echo "Unknown option: $1" >&2; exit 1 ;;
    *)             root="$1"; shift ;;
  esac
done

[[ -d $root ]] || { echo "Not a directory: $root" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found" >&2; exit 1; }

# probe_dur <file> -> echoes duration in seconds (float), or empty on failure.
probe_dur() {
  ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null
}

# probe_wh <file> -> echoes "<width> <height>" of the first video stream.
probe_wh() {
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
    -of csv=p=0:s=x "$1" 2>/dev/null | head -1 | tr 'x' ' '
}

mapfile -d '' -t files < <(find "$root" -type f -iname '*.avi' -print0)
total=${#files[@]}
if (( total == 0 )); then
  echo "No .avi files found under: $root" >&2
  exit 0
fi

(( do_delete )) && mode="DELETE" || mode="DRY-RUN (no files removed; add --delete to remove)"
echo "Mode: $mode"
echo "Tolerance: within ${tol_sec}s OR ${tol_pct}% of avi duration"
echo

matched=0 deleted=0 skipped=0 freed=0
for avi in "${files[@]}"; do
  mp4="${avi%.*}.mp4"
  printf '• %s\n' "$avi"

  if [[ ! -e $mp4 ]]; then
    echo "    no matching .mp4  -> keep"
    (( ++skipped )); continue
  fi

  dur_avi=$(probe_dur "$avi"); dur_mp4=$(probe_dur "$mp4")
  read -r w_avi h_avi < <(probe_wh "$avi"); read -r w_mp4 h_mp4 < <(probe_wh "$mp4")

  if [[ -z ${dur_avi:-} || -z ${dur_mp4:-} ]]; then
    echo "    could not read duration  -> keep (unsafe)"
    (( ++skipped )); continue
  fi

  # Decide match: resolution equal AND duration within either bound.
  verdict=$(awk -v da="$dur_avi" -v dm="$dur_mp4" \
                -v wa="${w_avi:-0}" -v ha="${h_avi:-0}" \
                -v wm="${w_mp4:-0}" -v hm="${h_mp4:-0}" \
                -v ts="$tol_sec" -v tp="$tol_pct" '
    BEGIN {
      diff = da - dm; if (diff < 0) diff = -diff;
      pct  = (da > 0) ? diff / da * 100 : 999;
      res_ok = (wa == wm && ha == hm);
      dur_ok = (diff <= ts || pct <= tp);
      printf "%.2f %.2f %.3f %.3f %d %d", da, dm, diff, pct, res_ok, dur_ok;
    }')
  read -r pd_avi pd_mp4 pdiff ppct res_ok dur_ok <<<"$verdict"

  printf '    avi %ss %sx%s | mp4 %ss %sx%s | Δ%ss (%s%%)\n' \
    "$pd_avi" "$w_avi" "$h_avi" "$pd_mp4" "$w_mp4" "$h_mp4" "$pdiff" "$ppct"

  reasons=""
  (( res_ok )) || reasons+=" resolution-mismatch"
  (( dur_ok )) || reasons+=" duration-mismatch"

  if [[ -n $reasons ]]; then
    echo "    NOT a clean match ->${reasons}  -> keep .avi"
    (( ++skipped )); continue
  fi

  (( ++matched ))
  sz=$(stat -c%s "$avi" 2>/dev/null || echo 0)
  if (( do_delete )); then
    rm -f -- "$avi" && echo "    match -> deleted .avi" && (( ++deleted, freed += sz ))
  else
    echo "    match -> would delete .avi"
    (( freed += sz ))
  fi
done

echo
printf 'Scanned %d avi | matched %d | kept %d\n' "$total" "$matched" "$skipped"
if (( do_delete )); then
  printf 'Deleted %d .avi, freed %.2f GB\n' "$deleted" "$(awk "BEGIN{print $freed/1073741824}")"
else
  printf 'Would delete %d .avi, freeing %.2f GB  (re-run with --delete)\n' \
    "$matched" "$(awk "BEGIN{print $freed/1073741824}")"
fi
