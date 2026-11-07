#!/bin/bash
# Send commands to the running driver and print its replies:
#   drv.sh "tap Messages" "wait 1.5" "labels"
source "$(dirname "$0")/env.sh"
mkdir -p "$IO"
SEQ=$(date +%s)$RANDOM$RANDOM
{ echo "$SEQ"; for c in "$@"; do echo "$c"; done; } > "$IO/cmd.tmp" && mv "$IO/cmd.tmp" "$IO/cmd.txt"
for i in $(seq 1 ${DRV_TIMEOUT_TICKS:-300}); do
  if [ -f "$IO/out.txt" ] && [ "$(head -1 "$IO/out.txt")" = "$SEQ" ]; then tail -n +2 "$IO/out.txt"; exit 0; fi
  sleep 0.2
done
echo TIMEOUT; exit 1
