#!/bin/bash
# Screenshot at point size (so pixel coords == tapxy coords): shot.sh <name>
source "$(dirname "$0")/env.sh"
f="$SHOTS/$1.png"
xcrun simctl io "$SIM" screenshot $(io_display) --type=png "$f" >/dev/null 2>&1 || exit 1
w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
sips --resampleWidth $((w / SCALE)) "$f" >/dev/null && echo "$f"
