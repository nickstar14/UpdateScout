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

# SwiftPM records the *deployment target* (15.0) as the linked-SDK version in
# LC_BUILD_VERSION. AppKit uses that field to pick the UI generation, so the
# app would render in pre-Liquid-Glass compatibility mode (old traffic lights,
# rounded-rect buttons, .glass styles silently falling back). Stamp the real
# SDK version so macOS 26+ draws the current design.
SDK_VERSION=$(xcrun --show-sdk-version)
vtool -set-build-version macos 15.0 "$SDK_VERSION" -replace \
      -output "$APP/Contents/MacOS/UpdateScout" "$APP/Contents/MacOS/UpdateScout"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string macosx$SDK_VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :DTPlatformVersion string $SDK_VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
# Compile the Icon Composer source. On macOS 26+ the system renders the
# layered Assets.car icon natively with Liquid Glass; a bare .icns is treated
# as a legacy icon and drawn inside a grey squircle frame. actool also emits a
# flattened AppIcon.icns as the fallback for older macOS.
xcrun actool Resources/AppIcon.icon \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 15.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$(mktemp)" \
    --errors --warnings >/dev/null

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
