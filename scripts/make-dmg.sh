#!/usr/bin/env bash
#
# make-dmg.sh — build the disk image that goes to other people.
#
# A DMG rather than a .pkg: an installer package would also have to be signed to
# open without a fight, so it buys nothing here, and drag-to-Applications is the
# shape macOS users already know. The app inside is universal and signed with
# whatever identity package-app.sh found.
#
# What this cannot fix is notarization. Anything downloaded arrives with a
# quarantine attribute, and macOS refuses to run unnotarized quarantined code —
# measured, not assumed: an ad-hoc build, a self-signed build and a build signed
# by an untrusted certificate are killed identically, and all three run once the
# attribute is removed. So the first-run note ships inside the image.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="M14t Touch"
VOLUME_NAME="M14t Touch"
VERSION="$(git describe --tags --always 2>/dev/null || echo "0.4.0")"
DMG="build/M14t-Touch-${VERSION}.dmg"

./scripts/package-app.sh release

APP="build/${APP_NAME}.app"
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

# Both architectures or it is not going to a friend with an Intel Mac.
ARCHS="$(lipo -archs "$APP/Contents/MacOS/m14ttouch")"
case "$ARCHS" in
    *x86_64*arm64*|*arm64*x86_64*) ;;
    *) echo "❌ Not a universal binary (got: $ARCHS)" >&2; exit 1 ;;
esac

printf '\033[1mStaging the image\033[0m\n'
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp resources/dmg-first-run.txt "$STAGE/Прочитайте меня.txt"

rm -f "$DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" \
    -ov -format UDZO -quiet "$DMG"

printf '\033[32mBuilt %s\033[0m  (%s, %s)\n' \
    "$DMG" "$(du -h "$DMG" | cut -f1 | tr -d ' ')" "$ARCHS"
echo
echo "  Send that file. On the other Mac it needs one manual step to get past"
echo "  Gatekeeper — the note inside the image says which."
