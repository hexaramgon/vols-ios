#!/bin/bash
# Recent app logs (debugLog/print/os_log): logs.sh [minutes=5] [filter-substring]
source "$(dirname "$0")/env.sh"
pred='process == "Volspire"'
[ -n "$2" ] && pred="$pred AND eventMessage CONTAINS[c] \"$2\""
xcrun simctl spawn "$SIM" log show --last "${1:-5}m" --style compact --predicate "$pred" | tail -200
