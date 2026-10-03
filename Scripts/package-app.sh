#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
BUILD="$ROOT/.build/package-app"
APP="$BUILD/Dialkit macOS.app"

swift build --package-path "$ROOT" --scratch-path "$BUILD" -c "$CONFIGURATION" --product dialkit-macos
BIN="$(swift build --package-path "$ROOT" --scratch-path "$BUILD" -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/dialkit-macos" "$APP/Contents/MacOS/"
cp "$ROOT/Sources/DialKitMacOSApp/Resources/AppIcon.icns" "$APP/Contents/Resources/"
# Include SwiftPM resources inside the app's standard resource directory.
for bundle in "$BIN"/*.bundle; do
    [ -d "$bundle" ] || continue
    ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>dialkit-macos</string>
    <key>CFBundleIdentifier</key><string>dev.dialkit.macos</string>
    <key>CFBundleName</key><string>Dialkit macOS</string>
    <key>CFBundleDisplayName</key><string>Dialkit macOS</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"
