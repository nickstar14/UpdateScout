#!/bin/bash
# Build UpdateScout.app from the SwiftPM package.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
swift build -c "$CONFIG"

BIN=".build/$CONFIG/UpdateScout"
APP="build/UpdateScout.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/UpdateScout"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Embed Sparkle (the executable links it via @executable_path/../Frameworks).
SPARKLE=$(find .build/artifacts/sparkle -name Sparkle.framework -path "*macos*" | head -1)
[[ -z "$SPARKLE" ]] && SPARKLE=$(find .build/artifacts -name Sparkle.framework | head -1)
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"

# Ad-hoc sign (inside out) so notifications and launchd behave; replace with a
# real Developer ID identity if this ever gets distributed.
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/UpdateScout.app
    cp -R "$APP" /Applications/UpdateScout.app
    echo "Installed to /Applications/UpdateScout.app"
fi
