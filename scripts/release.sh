#!/bin/bash
# Cut a release: build, zip, EdDSA-sign, update appcast.xml, publish a GitHub
# release, and push the appcast.
# Usage: scripts/release.sh [--channel beta] <version> [notes.html] [notes.md]
# --channel beta tags the appcast item so only builds that allow the beta
# channel (a running beta, see SelfUpdaterDelegate) are offered it. Without it
# the item goes to everyone, 1.x included.
set -euo pipefail
cd "$(dirname "$0")/.."

CHANNEL=""
if [[ "${1:-}" == "--channel" ]]; then
    CHANNEL="${2:?--channel needs a name, e.g. beta}"
    shift 2
fi
USAGE="usage: scripts/release.sh [--channel beta] <version> [notes.html] [notes.md]"
VERSION="${1:?$USAGE}"
NOTES_HTML="${2:-}"   # shown in Sparkle's update window
NOTES_MD="${3:-}"     # shown on the GitHub release page

# The repo keeps its name until 2.0 has rolled out (rename plan, section 6);
# the app, zip and release title follow CFBundleName.
REPO="nickstar14/UpdateScout"
APP_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" Resources/Info.plist)
APP="build/$APP_NAME.app"
ZIP_NAME="$APP_NAME-$VERSION.zip"

# The live appcast is read from main, and the push below pushes main by name.
# Run anywhere else and the tag and GitHub release go out while the appcast
# users read never lists them.
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
    echo "Refusing to release from '$BRANCH': merge into main and run it there." >&2
    exit 1
fi

# Stamp the version into Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILDNUM=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILDNUM" Resources/Info.plist

scripts/build-app.sh

ZIP="build/$ZIP_NAME"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

SIGN_UPDATE=$(find .build/artifacts/sparkle -name sign_update -not -path "*old_dsa*" | head -1)
# sign_update's output already includes BOTH attributes: edSignature and length.
SIGNATURE=$("$SIGN_UPDATE" "$ZIP")
DATE=$(date -R)
URL="https://github.com/$REPO/releases/download/v$VERSION/$ZIP_NAME"

# Insert the new item at the top of the appcast. Done in Python rather than
# perl so HTML release notes (with |, $, @ and friends) go in verbatim. The
# notes land in <description>, which is what Sparkle's update window shows.
# Every new item requires Apple silicon (the binary is arm64 only).
python3 - "$VERSION" "$DATE" "$URL" "$BUILDNUM" "$SIGNATURE" "$NOTES_HTML" "$CHANNEL" <<'APPCAST_EOF'
import pathlib, sys
version, date, url, build, signature, notes, channel = sys.argv[1:8]
description = ""
if notes:
    html = pathlib.Path(notes).read_text().strip()
    description = f"            <description><![CDATA[{html}]]></description>\n"
channel_tag = f"            <sparkle:channel>{channel}</sparkle:channel>\n" if channel else ""
item = (f"        <item>\n"
        f"            <title>Version {version}</title>\n"
        f"            <pubDate>{date}</pubDate>\n"
        f"{description}"
        f"{channel_tag}"
        f"            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>\n"
        f"            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>\n"
        f"            <enclosure url=\"{url}\"\n"
        f"                sparkle:version=\"{build}\"\n"
        f"                sparkle:shortVersionString=\"{version}\"\n"
        f"                {signature}\n"
        f"                type=\"application/octet-stream\"/>\n"
        f"        </item>")
appcast = pathlib.Path("appcast.xml")
text = appcast.read_text()
appcast.write_text(text.replace("<language>en</language>", "<language>en</language>\n" + item, 1))
APPCAST_EOF

git add Resources/Info.plist appcast.xml
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin main --tags
if [[ -n "$NOTES_MD" ]]; then
    gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "$APP_NAME $VERSION" --notes-file "$NOTES_MD"
else
    gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "$APP_NAME $VERSION" --generate-notes
fi

echo "Released $VERSION — appcast updated, zip uploaded."
