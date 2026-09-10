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

# Notarization, when there is a Developer ID to notarize under. This is the
# step that removes the manual dance on the other Mac entirely: Apple stamps the
# image, `stapler` attaches the stamp to it, and Gatekeeper stops asking.
#
# Credentials are read from a keychain profile rather than passed here, so no
# secret goes near this file or the shell history. Create it once with:
#
#   xcrun notarytool store-credentials m14ttouch \
#       --apple-id <your Apple ID> --team-id <your team> --password <app-specific>
NOTARY_PROFILE="${NOTARY_PROFILE:-m14ttouch}"

if codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "Developer ID Application"; then
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        printf '\033[1mNotarizing\033[0m (a minute or two)\n'
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        echo "  Notarized and stapled — it opens on any Mac with no warning."
    else
        echo "  ⚠️  Signed with a Developer ID but no notary credentials found."
        echo "     Run: xcrun notarytool store-credentials $NOTARY_PROFILE …"
    fi
fi

printf '\033[32mBuilt %s\033[0m  (%s, %s)\n' \
    "$DMG" "$(du -h "$DMG" | cut -f1 | tr -d ' ')" "$ARCHS"
echo
if xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    echo "  Send that file. It opens on any Mac without a warning."
else
    echo "  Send that file. On the other Mac it needs one manual step to get past"
    echo "  Gatekeeper — the note inside the image says which."
fi
