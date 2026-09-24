#!/bin/bash
# Cut a release: build, zip, EdDSA-sign, update appcast.xml, publish a GitHub
# release, and push the appcast.
# Usage: scripts/release.sh 0.2.0 [notes.html] [notes.md]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [notes.html] [notes.md]}"
NOTES_HTML="${2:-}"   # shown in Sparkle's update window
NOTES_MD="${3:-}"     # shown on the GitHub release page
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
# sign_update's output already includes BOTH attributes: edSignature and length.
SIGNATURE=$("$SIGN_UPDATE" "$ZIP")
DATE=$(date -R)
URL="https://github.com/$REPO/releases/download/v$VERSION/UpdateScout-$VERSION.zip"

# Insert the new item at the top of the appcast. Done in Python rather than
# perl so HTML release notes (with |, $, @ and friends) go in verbatim. The
# notes land in <description>, which is what Sparkle's update window shows.
python3 - "$VERSION" "$DATE" "$URL" "$BUILDNUM" "$SIGNATURE" "$NOTES_HTML" <<'APPCAST_EOF'
import pathlib, sys
version, date, url, build, signature, notes = sys.argv[1:7]
description = ""
if notes:
    html = pathlib.Path(notes).read_text().strip()
    description = f"            <description><![CDATA[{html}]]></description>\n"
item = (f"        <item>\n"
        f"            <title>Version {version}</title>\n"
        f"            <pubDate>{date}</pubDate>\n"
        f"{description}"
        f"            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>\n"
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
    gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "UpdateScout $VERSION" --notes-file "$NOTES_MD"
else
    gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "UpdateScout $VERSION" --generate-notes
fi

echo "Released $VERSION — appcast updated, zip uploaded."
