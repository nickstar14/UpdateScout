#!/bin/bash
# Cut a release: build, zip, EdDSA-sign, update appcast.xml, publish a GitHub
# release, and push the appcast. Usage: scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
REPO="nickstar14/UpdateScout"

# Stamp the version into Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILDNUM=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILDNUM" Resources/Info.plist

scripts/build-app.sh

ZIP="build/UpdateScout-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/UpdateScout.app "$ZIP"

SIGN_UPDATE=$(find .build/artifacts/sparkle -name sign_update -not -path "*old_dsa*" | head -1)
SIGNATURE=$("$SIGN_UPDATE" "$ZIP")   # emits: sparkle:edSignature="..." length="..."
SIZE=$(stat -f %z "$ZIP")
DATE=$(date -R)
URL="https://github.com/$REPO/releases/download/v$VERSION/UpdateScout-$VERSION.zip"

# Prepend the new item into appcast.xml.
ITEM="        <item>\n            <title>Version $VERSION</title>\n            <pubDate>$DATE</pubDate>\n            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>\n            <enclosure url=\"$URL\"\n                sparkle:version=\"$BUILDNUM\"\n                sparkle:shortVersionString=\"$VERSION\"\n                $SIGNATURE\n                length=\"$SIZE\"\n                type=\"application/octet-stream\"/>\n        </item>"
perl -0pi -e "s|(<language>en</language>)|\$1\n$ITEM|" appcast.xml

git add Resources/Info.plist appcast.xml
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin main --tags
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "UpdateScout $VERSION" --generate-notes

echo "Released $VERSION — appcast updated, zip uploaded."
