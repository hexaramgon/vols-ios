#!/bin/bash
# Build the app for the simulator. Prints only errors, warnings and the result.
# Known pre-existing warnings are filtered out (UIScreen.main, URLAudioPlayer export,
# PushNotificationManager Sendable) so anything left is new.
source "$(dirname "$0")/env.sh"
cd "$REPO" && xcodebuild -project Volspire.xcodeproj -scheme Volspire \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$APP_DD" build 2>&1 \
  | grep -E "^/.*(error|warning): |\*\* BUILD" \
  | grep -vE "UIScreen\+Extensions.swift|URLAudioPlayer.swift|PushNotificationManager.swift" | sort -u
