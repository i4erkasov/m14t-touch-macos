#!/usr/bin/env bash
#
# package-app.sh — assemble the menu-bar application around the built binary.
#
# SwiftPM produces a bare executable; a menu-bar app needs a bundle with an
# Info.plist carrying LSUIElement. Doing that here rather than adopting an Xcode
# project keeps `swift build` and `swift test` as the single source of truth —
# the whole test suite and every workflow instruction in CLAUDE.md rests on them.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
APP_NAME="M14t Touch"
BUNDLE_ID="com.m14ttouch.app"   # must match ArgumentParser.appBundleIdentifier
DESTINATION="build/${APP_NAME}.app"

VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo "0.3.0-dev")"

printf '\033[1mBuilding (%s)\033[0m\n' "$CONFIGURATION"
swift build -c "$CONFIGURATION"
BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/m14ttouch"
[ -x "$BINARY" ] || { echo "no binary at $BINARY" >&2; exit 1; }

printf '\033[1mAssembling %s\033[0m\n' "$DESTINATION"
rm -rf "$DESTINATION"
mkdir -p "$DESTINATION/Contents/MacOS" "$DESTINATION/Contents/Resources"
cp "$BINARY" "$DESTINATION/Contents/MacOS/m14ttouch"

cat > "$DESTINATION/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>m14ttouch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- No Dock icon: this is a menu-bar utility (spec §13). -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature with a stable identifier. Not a real signing identity, but it
# keeps the bundle from being rejected outright. Note that the signature still
# changes when the binary does, so macOS may treat a rebuilt app as a new one
# and ask for Input Monitoring and Accessibility again — see the README.
codesign --force --sign - --identifier "$BUNDLE_ID" "$DESTINATION" 2>/dev/null \
    || echo "  (codesign unavailable — the bundle is unsigned)"

printf '\033[32mBuilt %s\033[0m\n' "$DESTINATION"
echo
echo "  Run it:      open \"$DESTINATION\""
echo "  Install it:  cp -R \"$DESTINATION\" ~/Applications/"
echo
echo "  It needs Input Monitoring and Accessibility granted to the app itself;"
echo "  the terminal's existing grants do not carry over to a new bundle."
