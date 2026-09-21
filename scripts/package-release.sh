#!/bin/bash
# Creates local distribution files only. Never creates or publishes a GitHub Release.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VIBE_VERSION:-0.1.0}"
APP="${1:-$PWD/dist/Vibe Statistics.app}"
/usr/bin/python3 scripts/check-bundle.py "$APP"
ACTUAL=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$ACTUAL" == "$VERSION" ]] || { echo 'App version does not match VIBE_VERSION' >&2; exit 1; }
ARCHIVE="Vibe-Statistics-$VERSION-arm64.zip"
mkdir -p dist
COPYFILE_DISABLE=1 ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
printf '%s\n' "dist/$ARCHIVE"
