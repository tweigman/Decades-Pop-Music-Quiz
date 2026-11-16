#!/bin/sh
# Build Pop Quiz and install it on the iPhone plugged into this Mac.
set -eu
cd "$(dirname "$0")"

XCODE=/Volumes/Macz500/Applications/Xcode.app/Contents/Developer
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "$XCODE" ]; then export DEVELOPER_DIR="$XCODE"; fi

xcodegen --quiet
LOG=build/build.log
mkdir -p build
if ! xcodebuild -project PopQuiz.xcodeproj -scheme PopQuiz -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
    -allowProvisioningUpdates build >"$LOG" 2>&1; then
    grep -E "error:" "$LOG" | sort -u
    echo "Build failed; full log in ios/$LOG"
    exit 1
fi
grep -E "warning: .*\.swift" "$LOG" | sort -u || true
APP=build/DerivedData/Build/Products/Release-iphoneos/PopQuiz.app

JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null
DEVICE=$(python3 - "$JSON" <<'EOF'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
phones = [d for d in devices
          if d["hardwareProperties"].get("reality") == "physical"
          and d["hardwareProperties"].get("platform") == "iOS"
          and d["connectionProperties"].get("tunnelState") != "unavailable"]
print(phones[0]["identifier"] if phones else "")
EOF
)
rm -f "$JSON"
[ -n "$DEVICE" ] || { echo "No iPhone found. Plug it in, unlock it and tap Trust."; exit 1; }

xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" com.tweigman.popquiz
