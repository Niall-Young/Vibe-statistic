#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PYTHONDONTWRITEBYTECODE=1
npm ci --prefix Helpers --ignore-scripts --no-audit --no-fund
/usr/bin/python3 -m pip install --target Helpers/vendor -r Helpers/requirements.txt --upgrade --disable-pip-version-check -q
swift build -c release
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
APP="${1:-$PWD/dist/Vibe Statistics.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/VibeStatistics "$APP/Contents/MacOS/VibeStatistics"
rsync -a --delete .build/release/VibeStatistics_VibeStatistics.bundle "$APP/Contents/Resources/"
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
rsync -a --delete --exclude '__pycache__' Helpers/ "$APP/Contents/Resources/Helpers/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VibeStatistics</string>
<key>CFBundleIdentifier</key><string>com.niallyoung.vibestatistics</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Vibe Statistics</string>
<key>CFBundleDisplayName</key><string>Vibe Statistics</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh_CN</string><string>en</string></array>
</dict></plist>
PLIST
# Local ad-hoc signature only; no Developer ID or notarization.
xattr -cr "$APP"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
