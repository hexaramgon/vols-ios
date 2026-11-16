#!/bin/bash
# Record an interaction and pull frames, for animations/transitions:
#   record.sh <name> <seconds> [fps] [-- drv commands...]
# Starts recording, runs the optional driver commands, stops after <seconds>,
# and writes <name>.mp4 plus <name>_NNN.png frames (point size) to the shots dir.
source "$(dirname "$0")/env.sh"
name=$1; secs=$2; fps=${3:-10}; shift 3 2>/dev/null; [ "$1" = "--" ] && shift
mp4="$SHOTS/$name.mp4"; rm -f "$mp4" "$SHOTS/${name}"_*.png
xcrun simctl io "$SIM" recordVideo $(io_display) --codec=h264 --force "$mp4" >/dev/null 2>&1 & rec=$!
sleep 1
[ $# -gt 0 ] && "$SKILL_DIR/scripts/drv.sh" "$@" >/dev/null &
sleep "$secs"; kill -INT $rec; wait $rec 2>/dev/null
w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$mp4")
ffmpeg -v error -y -i "$mp4" -vf "fps=$fps,scale=$((w / SCALE)):-1" "$SHOTS/${name}_%03d.png"
# simctl only writes a frame when the screen changes, so a mostly-still clip can
# be shorter than one fps tick — fall back to every recorded frame.
ls "$SHOTS/${name}"_*.png >/dev/null 2>&1 || \
  ffmpeg -v error -y -i "$mp4" -fps_mode passthrough -vf "scale=$((w / SCALE)):-1" "$SHOTS/${name}_%03d.png"
ls "$SHOTS/${name}"_*.png 2>/dev/null | wc -l | xargs echo "frames:"; echo "$mp4"
