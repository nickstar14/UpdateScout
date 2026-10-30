#!/bin/bash
# Build PrismPack.app from the SwiftPM package.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
# The bundle is named after CFBundleName; the executable inside keeps its own
# name (CFBundleExecutable, still UpdateScout under rename Plan A).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
swift build -c "$CONFIG"

APP_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" Resources/Info.plist)
EXE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" Resources/Info.plist)
# SwiftPM names the binary after the target; the bundle keeps CFBundleExecutable.
BIN=".build/$CONFIG/PrismPack"
APP="build/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/$EXE_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The 1.8.0 icon, for the one-time rename pop-up's "before" picture.
cp Resources/LegacyIcon.png "$APP/Contents/Resources/LegacyIcon.png"
cp Resources/AppIconDark.png "$APP/Contents/Resources/AppIconDark.png"

# SwiftPM records the *deployment target* (15.0) as the linked-SDK version in
# LC_BUILD_VERSION. AppKit uses that field to pick the UI generation, so the
# app would render in pre-Liquid-Glass compatibility mode (old traffic lights,
# rounded-rect buttons, .glass styles silently falling back). Stamp the real
# SDK version so macOS 26+ draws the current design.
SDK_VERSION=$(xcrun --show-sdk-version)
vtool -set-build-version macos 15.0 "$SDK_VERSION" -replace \
      -output "$APP/Contents/MacOS/$EXE_NAME" "$APP/Contents/MacOS/$EXE_NAME"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string macosx$SDK_VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :DTPlatformVersion string $SDK_VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
# Compile the Icon Composer source. On macOS 26+ the system renders the
# layered Assets.car icon natively with Liquid Glass; a bare .icns is treated
# as a legacy icon and drawn inside a grey squircle frame. actool also emits a
# flattened AppIcon.icns as the fallback for older macOS.
# Full paths: actool runs through a helper that can keep an earlier build's
# working directory, so relative paths may land in another checkout.
xcrun actool "$PWD/Resources/AppIcon.icon" \
    --compile "$PWD/$APP/Contents/Resources" \
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
    # The pre-rename copy is the same app (same bundle ID): replace it rather
    # than leave two. The launch agent repairs its path on the next launch.
    rm -rf /Applications/UpdateScout.app "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    echo "Installed to /Applications/$APP_NAME.app"
fi
