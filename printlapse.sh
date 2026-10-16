#!/usr/bin/env bash
# Captures Buddy3D camera frames while a Prusa printer is printing and stitches them into an MP4.
# Manual stitch: printlapse.sh stitch <frames-folder>
set -u

INTERVAL="${INTERVAL:-10}"
FPS="${FPS:-30}"
HOLD_END="${HOLD_END:-3}"
KEEP_FRAMES="${KEEP_FRAMES:-false}"
OFFLINE_LIMIT="${OFFLINE_LIMIT:-600}"
FRAMES_DIR="${FRAMES_DIR:-/frames}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"

log() { echo "$(date '+%F %T') $*" >&2; }

api() {
  curl -fsS -m 5 --digest -u "${PRUSALINK_USER}:${PRUSALINK_PASS}" "${PRINTER_URL%/}$1"
}

printer_state() {
  local json
  if json="$(api /api/v1/status 2>/dev/null)"; then
    jq -r '.printer.state // "UNKNOWN"' <<<"$json"
  else
    echo "UNREACHABLE"
  fi
}

job_name() {
  local json name
  json="$(api /api/v1/job 2>/dev/null)" || { echo "print"; return; }
  name="$(jq -r '.file.display_name // .file.name // "print"' <<<"$json")"
  name="$(tr -c 'A-Za-z0-9._-' '_' <<<"${name%.*}" | sed 's/_*$//')"
  echo "${name:-print}"
}

grab_frame() {
  timeout 20 ffmpeg -nostdin -loglevel error -rtsp_transport tcp \
    -i "$CAMERA_URL" -frames:v 1 -q:v 2 -y "$1"
}

stitch() {
  local dir="$1" count out
  count=$(find "$dir" -maxdepth 1 -name '*.jpg' | wc -l)
  if [ "$count" -lt 2 ]; then
    log "Only $count frame(s) in $dir, removing."
    rm -rf "$dir"
    return
  fi
  mkdir -p "$OUTPUT_DIR"
  out="${OUTPUT_DIR}/$(basename "$dir").mp4"
  log "Stitching $count frames -> $out"
  if ffmpeg -nostdin -loglevel error -framerate "$FPS" -i "$dir/%06d.jpg" \
       -vf "tpad=stop_mode=clone:stop_duration=${HOLD_END}" \
       -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
       -movflags +faststart -y "$out"; then
    log "Done: $out"
    if [ "$KEEP_FRAMES" = "true" ]; then
      mkdir -p "${OUTPUT_DIR}/frames" && mv "$dir" "${OUTPUT_DIR}/frames/"
    else
      rm -rf "$dir"
    fi
  else
    log "ffmpeg failed, frames left in $dir"
  fi
}

if [ "${1:-}" = "stitch" ]; then
  stitch "${2:?usage: printlapse.sh stitch <frames-folder>}"
  exit 0
fi

: "${CAMERA_URL:?CAMERA_URL is required}"
: "${PRINTER_URL:?PRINTER_URL is required}"
: "${PRUSALINK_PASS:?PRUSALINK_PASS is required}"
PRUSALINK_USER="${PRUSALINK_USER:-maker}"

mkdir -p "$FRAMES_DIR" "$OUTPUT_DIR"

# Finish sessions left over from a restart.
for d in "$FRAMES_DIR"/*/; do
  [ -d "$d" ] && stitch "${d%/}"
done

log "Watching $PRINTER_URL, camera $CAMERA_URL, one frame every ${INTERVAL}s"

session=""
frame=0
offline_since=0

while true; do
  state="$(printer_state)"
  now=$(date +%s)

  case "$state" in
    PRINTING)
      offline_since=0
      if [ -z "$session" ]; then
        session="${FRAMES_DIR}/$(date '+%Y-%m-%d_%H%M')_$(job_name)"
        mkdir -p "$session"
        frame=0
        log "Print started, recording to $session"
      fi
      if grab_frame "$(printf '%s/%06d.jpg' "$session" $((frame + 1)))"; then
        frame=$((frame + 1))
      else
        log "Frame grab failed, will retry"
      fi
      ;;
    PAUSED|ATTENTION|BUSY)
      offline_since=0
      ;;
    UNREACHABLE)
      if [ -n "$session" ]; then
        [ "$offline_since" -eq 0 ] && offline_since=$now && log "Printer unreachable"
        if [ $((now - offline_since)) -ge "$OFFLINE_LIMIT" ]; then
          log "Printer gone for ${OFFLINE_LIMIT}s, closing session"
          stitch "$session"; session=""; offline_since=0
        fi
      fi
      ;;
    *)
      offline_since=0
      if [ -n "$session" ]; then
        log "Print ended ($state)"
        stitch "$session"
        session=""
      fi
      ;;
  esac

  sleep "$INTERVAL"
done
