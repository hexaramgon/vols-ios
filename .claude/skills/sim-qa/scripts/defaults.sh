#!/bin/bash
# The app's UserDefaults live in its data container — `simctl spawn defaults`
# doesn't reach them. Usage: defaults.sh [read|delete <key>]
source "$(dirname "$0")/env.sh"
C=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data) || exit 1
P="$C/Library/Preferences/$BUNDLE.plist"
case "$1" in
  delete) xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null; plutil -remove "$2" "$P" && echo "removed $2" ;;
  *) plutil -p "$P" ;;
esac
