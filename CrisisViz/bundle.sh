#!/bin/bash
# Build CrisisViz.app — a proper macOS application bundle.
#
#   ./bundle.sh         build, package, and launch via `open`
#   ./bundle.sh --no-launch    build only
#
# The bundle has a real Info.plist + AppIcon.icns + crisis_data.json, so when
# launched with `open CrisisViz.app` it appears in the Dock with its icon and
# behaves like a native macOS application.

set -euo pipefail
cd "$(dirname "$0")"

APP=CrisisViz.app
BIN_NAME=CrisisViz
BUNDLE_ID=org.crisis.CrisisViz
VERSION=1.0
BUILD=1
LAUNCH=1

for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=0 ;;
    esac
done

echo "▸ Generating AppIcon.icns…"
swift Tools/MakeAppIcon.swift > /dev/null
iconutil -c icns AppIcon.iconset -o AppIcon.icns

echo "▸ Building release binary…"
swift build -c release

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp ".build/release/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Sources/CrisisViz/crisis_data.json "$APP/Contents/Resources/crisis_data.json"

# Copy any other Bundle.module resources that SwiftPM placed alongside the binary
# so they are still findable from Bundle.main when running from the .app.
if [ -d ".build/release/${BIN_NAME}_${BIN_NAME}.bundle" ]; then
    cp -R ".build/release/${BIN_NAME}_${BIN_NAME}.bundle" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>      <string>en</string>
    <key>CFBundleExecutable</key>             <string>${BIN_NAME}</string>
    <key>CFBundleIconFile</key>               <string>AppIcon</string>
    <key>CFBundleIdentifier</key>             <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>  <string>6.0</string>
    <key>CFBundleName</key>                   <string>CrisisViz</string>
    <key>CFBundleDisplayName</key>            <string>CrisisViz</string>
    <key>CFBundlePackageType</key>            <string>APPL</string>
    <key>CFBundleShortVersionString</key>     <string>${VERSION}</string>
    <key>CFBundleVersion</key>                <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>         <string>14.0</string>
    <key>LSApplicationCategoryType</key>      <string>public.app-category.education</string>
    <key>NSPrincipalClass</key>               <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>        <true/>
    <key>NSSupportsAutomaticTermination</key> <true/>
    <key>NSSupportsSuddenTermination</key>    <true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so macOS treats it as a signed app bundle.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

# Refresh the icon cache so Finder & Dock pick up the new icon immediately.
touch "$APP"

echo "✓ Built $APP"

if [ "$LAUNCH" -eq 1 ]; then
    echo "▸ Launching ${APP}…"
    open "$APP"
fi
