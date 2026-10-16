#!/bin/bash
# Run by DSM Task Scheduler as root. Prints a line per new timelapse and exits 1 so DSM emails the output.
TL_DIR="${1:-/volume1/docker/printlapse/timelapses}"
SEEN="$TL_DIR/.notified"

[ -d "$TL_DIR" ] || { echo "Folder not found: $TL_DIR"; exit 2; }
touch "$SEEN"

new=0
now=$(date +%s)
for f in "$TL_DIR"/*.mp4; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  grep -qxF "$name" "$SEEN" && continue
  [ $(( now - $(stat -c %Y "$f") )) -lt 60 ] && continue

  share_path="/${f#/volume*/}"
  link=""
  if command -v synowebapi >/dev/null 2>&1; then
    resp=$(synowebapi --exec api=SYNO.FileStation.Sharing method=create version=3 \
             path="$share_path" 2>/dev/null)
    link=$(printf '%s' "$resp" | tr -d '\\' | grep -o '"url" *: *"[^"]*"' | head -1 | cut -d'"' -f4)
  fi

  echo "Timelapse ready: ${name%.mp4}"
  if [ -n "$link" ]; then
    echo "Watch or download: $link"
  else
    echo "Saved on the NAS: $share_path"
  fi
  echo
  echo "$name" >>"$SEEN"
  new=1
done

exit $new
