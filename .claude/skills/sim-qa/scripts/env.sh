# Shared settings, sourced by every script. Override any of these in the environment.
#   SIM     simulator UDID (default: the signed-in iPhone sim)
#   QA_DIR  work dir for builds, driver io, screenshots (point it at the session scratchpad)
#   SCALE   device pixel scale, used to shrink screenshots to point size (3 for modern iPhones, 2 for SE)
SIM=${SIM:-A77F9C00-A82A-422F-9E6E-EC34152422F1}
# Simulator UDIDs are per-machine. If this one isn't on this Mac (a new
# laptop), fall back to a booted iPhone, then the newest available non-SE iPhone.
if ! xcrun simctl list devices 2>/dev/null | grep -q "$SIM"; then
  SIM=$(xcrun simctl list devices booted 2>/dev/null | grep -E '^ +iPhone' | grep -v ' SE' | head -1 | grep -oE '[0-9A-F-]{36}')
  [ -z "$SIM" ] && SIM=$(xcrun simctl list devices available 2>/dev/null | grep -E '^ +iPhone' | grep -v ' SE' | tail -1 | grep -oE '[0-9A-F-]{36}')
fi
QA_DIR=${QA_DIR:-${TMPDIR:-/tmp}/volspire-sim-qa}
SCALE=${SCALE:-3}
BUNDLE=com.volspire.app
SKILL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPO=$(git -C "$SKILL_DIR" rev-parse --show-toplevel)
APP_DD=$QA_DIR/dd-app
APP=$APP_DD/Build/Products/Debug-iphonesimulator/Volspire.app
IO=$QA_DIR/driver/io
SHOTS=$QA_DIR/shots
mkdir -p "$QA_DIR" "$SHOTS"
