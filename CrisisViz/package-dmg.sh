#!/bin/bash
# Build CrisisViz.dmg — an ad-hoc-signed disk image for distribution.
#
#   ./package-dmg.sh
#
# Produces CrisisViz.dmg in the current directory containing the assembled
# CrisisViz.app plus a symlink to /Applications, so the installer can drag
# the app onto the Applications shortcut. The DMG is read-only, compressed
# (UDZO), and ad-hoc signed.
#
# Gatekeeper note: ad-hoc signing means the first launch on a new Mac will
# show "macOS cannot verify the developer of CrisisViz". Right-click the app
# in /Applications → Open → Open in the confirmation dialog. macOS remembers
# the decision; subsequent launches behave normally.

set -euo pipefail
cd "$(dirname "$0")"

APP=CrisisViz.app
DMG=CrisisViz.dmg
VOLNAME=CrisisViz
STAGE=$(mktemp -d -t crisisviz-dmg)
trap 'rm -rf "$STAGE"' EXIT

# 1. Ensure the .app bundle exists. If not, build it without launching.
if [ ! -d "$APP" ]; then
    echo "==> $APP not found — running bundle.sh first..."
    ./bundle.sh --no-launch
fi

# Defensive: confirm the executable is actually inside the bundle.
if [ ! -x "$APP/Contents/MacOS/CrisisViz" ]; then
    echo "!! $APP exists but the executable is missing. Run ./bundle.sh manually." >&2
    exit 1
fi

# 2. Re-codesign the app (ad-hoc) and clear any quarantine attributes.
echo "==> Codesigning $APP (ad-hoc)..."
codesign --force --deep --sign - "$APP" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# 3. Stage the DMG layout: the .app + a symlink to /Applications.
echo "==> Staging DMG layout in $STAGE..."
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 4. Build the compressed read-only DMG.
echo "==> Creating $DMG (UDZO, compressed)..."
rm -f "$DMG"
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    -quiet \
    "$DMG"

# 5. Ad-hoc sign the DMG itself so macOS treats it as a signed artifact.
echo "==> Codesigning $DMG (ad-hoc)..."
codesign --force --sign - "$DMG" 2>/dev/null || true

# 6. Verify and report.
echo "==> Verifying $DMG..."
hdiutil verify -quiet "$DMG"

SIZE=$(du -h "$DMG" | awk '{print $1}')
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')

cat <<INFO

OK Built $DMG  ($SIZE)
  SHA-256: $SHA

Install on a target Mac:
  1. Copy $DMG to the target machine.
  2. Double-click to mount the volume.
  3. Drag $APP onto the Applications shortcut.
  4. Eject the volume.
  5. First launch: right-click /Applications/$APP → Open → Open.
INFO
