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

# One place decides what a version is called, in both of its forms.
. "$(dirname "$0")/version.sh"
VERSION_TAG="$(version_tag)"
VERSION="$(version_bundle "$VERSION_TAG")"

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

# The icon. Not decoration: the app has no Dock presence, so this is what
# identifies it in Finder, in the disk image, and — the one that matters — in
# the Privacy & Security lists where its permissions are granted.
if [ -f resources/AppIcon.icns ]; then
    cp resources/AppIcon.icns "$DESTINATION/Contents/Resources/AppIcon.icns"
else
    echo "  (no resources/AppIcon.icns — run scripts/make-app-icon.swift)"
fi

cat > "$DESTINATION/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>m14ttouch</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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
# A Developer ID first, because that is the only signature other Macs trust,
# and it is the one notarization requires. The local self-signed identity is the
# fallback for this machine; ad-hoc is the fallback for having neither.
# `|| true` because not finding one is the normal case, and `set -e` would
# otherwise treat grep's "no match" as a failure and stop the build here.
DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/.*"(.*)"/\1/' || true)"
LOCAL_IDENTITY="M14t Touch Local"

if [ -n "$DEVELOPER_ID" ]; then
    # The hardened runtime is required for notarization. It costs nothing here:
    # nothing in this app injects, and the one private symbol is resolved from a
    # system framework, which the hardened runtime allows.
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID" --identifier "$BUNDLE_ID" "$DESTINATION" \
        && echo "  Signed with \"$DEVELOPER_ID\" — ready to notarize."
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$LOCAL_IDENTITY"; then
    codesign --force --sign "$LOCAL_IDENTITY" --identifier "$BUNDLE_ID" "$DESTINATION" \
        && echo "  Signed as \"$LOCAL_IDENTITY\" — permissions survive rebuilds here,"
    echo "  but other Macs will not trust it. See README, \"Sharing it\"."
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$DESTINATION" 2>/dev/null \
        || echo "  (codesign unavailable — the bundle is unsigned)"
    echo "  Ad-hoc signed. Run scripts/make-signing-identity.sh once to stop"
    echo "  macOS asking for Input Monitoring again after every rebuild."
fi

# The bundle is the artifact; check the artifact. A release goes to other
# people's Macs and to a Homebrew cask that states the same version, so a
# mismatch here is caught before it is published rather than after.
if ! assert_bundle_version "$DESTINATION" "$VERSION"; then
    echo "   (built from $VERSION_TAG)" >&2
    exit 1
fi

printf '\033[32mBuilt %s\033[0m  (version %s)\n' "$DESTINATION" "$VERSION"
echo
echo "  Run it:      open \"$DESTINATION\""
echo "  Install it:  cp -R \"$DESTINATION\" ~/Applications/"
echo
echo "  It needs Input Monitoring and Accessibility granted to the app itself;"
echo "  the terminal's existing grants belong to a different binary. With a"
echo "  signing identity they are granted once and survive later builds."
