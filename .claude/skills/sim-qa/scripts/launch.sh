#!/bin/bash
# Install the last build and (re)launch it. Extra KEY=VALUE args become launch
# environment (SIMCTL_CHILD_KEY) — that's how QA-TEMP hooks are switched on:
#   launch.sh QA_OPEN_CONVO=psyknick
source "$(dirname "$0")/env.sh"
xcrun simctl boot "$SIM" 2>/dev/null
open -b com.apple.iphonesimulator 2>/dev/null  # show the window if Simulator.app is installed (headless works either way)
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null
xcrun simctl install "$SIM" "$APP" || exit 1
envs=(); for kv in "$@"; do envs+=("SIMCTL_CHILD_$kv"); done
env "${envs[@]}" xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null && echo "launched on $SIM"
