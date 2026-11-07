#!/bin/bash
# start | stop the XCUITest driver that drv.sh talks to. The app should already be running.
source "$(dirname "$0")/env.sh"
D=$QA_DIR/driver
case "$1" in
  start)
    pkill -f "DriverUITests" 2>/dev/null
    mkdir -p "$D" && rsync -a --delete --exclude io --exclude dd --exclude '*.log' "$SKILL_DIR/driver/" "$D/" && mkdir -p "$IO" && rm -f "$IO"/*
    cd "$D" && xcodebuild -project Driver.xcodeproj -scheme DriverUITests -destination "platform=iOS Simulator,id=$SIM" \
      -derivedDataPath "$D/dd" build-for-testing 2>&1 | grep -E "error:|\*\* BUILD" | tail -3
    (TEST_RUNNER_DRIVER_IO="$IO" xcodebuild -project Driver.xcodeproj -scheme DriverUITests \
      -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$D/dd" test-without-building > "$D/test.log" 2>&1 &)
    # Wait for the loop to answer (the runner takes ~20s to come up).
    for i in $(seq 1 30); do
      out=$("$SKILL_DIR/scripts/drv.sh" "activate" 2>/dev/null) && [[ "$out" == *ok* ]] && { echo "driver ready"; exit 0; }
      sleep 2
    done
    echo "driver did not start — see $D/test.log"; exit 1 ;;
  stop)
    pkill -f "DriverUITests" 2>/dev/null; echo stopped ;;
  *) echo "usage: driver.sh start|stop"; exit 2 ;;
esac
