#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PYTHONDONTWRITEBYTECODE=1
VERSION="${VIBE_VERSION:-0.1.0}"
BUILD="${VIBE_BUILD:-1}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VIBE_VERSION must be MAJOR.MINOR.PATCH' >&2; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo 'VIBE_BUILD must be numeric' >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { echo 'Build on Apple Silicon' >&2; exit 1; }
/usr/bin/python3 scripts/prepare-runtime.py
export PATH="$PWD/.build/Runtime/node/bin:$PATH"
PYTHON="$PWD/.build/Runtime/python/bin/python3"
npm ci --prefix Helpers --ignore-scripts --no-audit --no-fund
"$PYTHON" -I -m pip install --target Helpers/vendor -r Helpers/requirements.txt --upgrade --disable-pip-version-check -q
cp Helpers/vendor/certifi/cacert.pem .build/Runtime/cacert.pem
swift build -c release
cat Sources/VibeStatistics/DesignSystem/NicoSVGPath.swift scripts/make-icon.swift > .build/make-icon.swift
swift .build/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
APP="${1:-$PWD/dist/Vibe Statistics.app}"
# Always assemble a fresh bundle, so old/development files cannot leak into an artifact.
STAGE="$(mktemp -d /tmp/vibe-bundle.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/Vibe Statistics.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/Helpers" "$BUNDLE/Contents/Resources/Branding"
cp .build/release/VibeStatistics "$BUNDLE/Contents/MacOS/VibeStatistics"
cp -R .build/release/VibeStatistics_VibeStatistics.bundle "$BUNDLE/Contents/Resources/"
cp .build/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp Resources/Branding/Creature.svg "$BUNDLE/Contents/Resources/Branding/"
cp Helpers/bridge.py Helpers/query.sb Helpers/qoder.mjs Helpers/package.json Helpers/package-lock.json Helpers/requirements.txt "$BUNDLE/Contents/Resources/Helpers/"
rsync -a --exclude '__pycache__' Helpers/vendor Helpers/node_modules "$BUNDLE/Contents/Resources/Helpers/"
rsync -a --exclude '__pycache__' .build/Runtime "$BUNDLE/Contents/Resources/"
cp THIRD_PARTY_NOTICES.md "$BUNDLE/Contents/Resources/"
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VibeStatistics</string>
<key>CFBundleIdentifier</key><string>com.niallyoung.vibestatistics</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Vibe Statistics</string>
<key>CFBundleDisplayName</key><string>Vibe Statistics</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh_CN</string><string>en</string></array>
</dict></plist>
PLIST
xattr -cr "$BUNDLE"
# Sign nested Mach-O code first, then the app. No Developer ID or notarization.
/usr/bin/python3 scripts/check-bundle.py "$BUNDLE" --sign
codesign --force --sign - "$BUNDLE"
/usr/bin/python3 scripts/check-bundle.py "$BUNDLE"
mkdir -p "$(dirname "$APP")"
# Only replace a recognizable prior build, not an arbitrary directory.
if [[ -e "$APP" ]]; then
    [[ -f "$APP/Contents/MacOS/VibeStatistics" ]] || { echo 'Output exists and is not a Vibe Statistics app' >&2; exit 1; }
    rm -rf "$APP"
fi
mv "$BUNDLE" "$APP"
printf '%s\n' "$APP"
