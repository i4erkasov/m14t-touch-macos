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

# A release goes to other people's Macs, which are not all Apple Silicon, so it
# is built for both architectures. A debug build is for this machine and is
# built natively, because doubling its build time to produce a slice nobody runs
# would only slow the edit-run loop down.
if [ "$CONFIGURATION" = "release" ]; then
    ARCHS=(--arch arm64 --arch x86_64)
else
    ARCHS=()
fi

printf '\033[1mBuilding (%s)\033[0m\n' "$CONFIGURATION"
swift build -c "$CONFIGURATION" "${ARCHS[@]+"${ARCHS[@]}"}"
BINARY="$(swift build -c "$CONFIGURATION" "${ARCHS[@]+"${ARCHS[@]}"}" --show-bin-path)/m14ttouch"
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

# Sign with a real identity when there is one, because that is what decides
# whether the app keeps its permissions. macOS keys Input Monitoring and
# Accessibility on the designated requirement; an ad-hoc signature pins the
# binary's exact bytes, so every rebuild is a new application that has to be
# granted them again. A certificate gives a requirement the next build also
# satisfies. `scripts/make-signing-identity.sh` creates a local one.
IDENTITY="M14t Touch Local"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$DESTINATION" \
        && echo "  Signed as \"$IDENTITY\" — permissions survive rebuilds."
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$DESTINATION" 2>/dev/null \
        || echo "  (codesign unavailable — the bundle is unsigned)"
    echo "  Ad-hoc signed. Run scripts/make-signing-identity.sh once to stop"
    echo "  macOS asking for Input Monitoring again after every rebuild."
fi

printf '\033[32mBuilt %s\033[0m\n' "$DESTINATION"
echo
echo "  Run it:      open \"$DESTINATION\""
echo "  Install it:  cp -R \"$DESTINATION\" ~/Applications/"
echo
echo "  It needs Input Monitoring and Accessibility granted to the app itself;"
echo "  the terminal's existing grants belong to a different binary. With a"
echo "  signing identity they are granted once and survive later builds."
