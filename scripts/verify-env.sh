#!/usr/bin/env bash
#
# verify-env.sh — check that this machine can build, test and run m14ttouch.
#
# Exits non-zero if anything required is missing.

set -uo pipefail
cd "$(dirname "$0")/.."

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; FAILED=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

FAILED=0

head_ "Toolchain"

if ! command -v swift >/dev/null 2>&1; then
    bad "swift not found — run: xcode-select --install"
else
    ok "swift $(swift --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9.]*\).*/\1/p' | head -1)"
fi

DEVDIR="$(xcode-select -p 2>/dev/null || echo '')"
case "$DEVDIR" in
    *Xcode*)
        ok "active developer dir: $DEVDIR"
        ;;
    "")
        bad "no active developer directory (xcode-select -p failed)"
        ;;
    *)
        bad "active developer dir is Command Line Tools: $DEVDIR"
        printf '      swift test needs full Xcode. Install it from the App Store, then:\n'
        printf '      sudo xcode-select -s /Applications/Xcode.app/Contents/Developer\n'
        printf '      sudo xcodebuild -license accept\n'
        ;;
esac

# XCTest is the thing CLT actually lacks — probe for it directly.
if [ -n "$DEVDIR" ] && find "$DEVDIR" -name 'XCTest.swiftmodule' -maxdepth 8 2>/dev/null | grep -q .; then
    ok "XCTest available"
else
    bad "XCTest not found — 'swift test' will fail with: no such module 'XCTest'"
fi

head_ "Repository"

if git remote get-url upstream >/dev/null 2>&1; then
    ok "upstream remote: $(git remote get-url upstream)"
else
    warn "no 'upstream' remote — add with:"
    printf '      git remote add upstream https://github.com/talesmousinho/m14t-touch-macos.git\n'
fi

[ -f M14t_Touch_Manager_TZ.md ] && ok "spec present: M14t_Touch_Manager_TZ.md" \
                                || warn "spec M14t_Touch_Manager_TZ.md missing"

head_ "Build"

if swift build >/tmp/m14t-build.log 2>&1; then
    ok "swift build"
else
    bad "swift build failed — see /tmp/m14t-build.log"
fi

head_ "Tests"

if swift test >/tmp/m14t-test.log 2>&1; then
    ok "swift test — $(grep -cE '^Test Case .* passed' /tmp/m14t-test.log 2>/dev/null || echo '?') cases passed"
else
    if grep -q "no such module 'XCTest'" /tmp/m14t-test.log 2>/dev/null; then
        bad "swift test failed: XCTest missing (install full Xcode — see above)"
    else
        bad "swift test failed — see /tmp/m14t-test.log"
    fi
fi

head_ "Hardware (informational — not required to build)"

# Probed through ioreg, not system_profiler: `system_profiler SPUSBDataType`
# returns nothing at all on macOS 26 even with devices attached, which reported
# a connected M14t as missing. ioreg is also closer to what the driver sees —
# it matches on HID usage page 0x0D (digitizer), usage 0x04 (touch screen).
DIGITIZERS=$(ioreg -c IOHIDDevice -r -d1 2>/dev/null | grep -c '"PrimaryUsagePage" = 13')

if [ "${DIGITIZERS:-0}" -gt 0 ]; then
    ok "HID digitizer interfaces present: $DIGITIZERS"
    ioreg -p IOUSB -w0 2>/dev/null \
        | grep -iE 'multitouch|thinkvision|m14t|digitizer' \
        | sed 's/^[^+]*+-o /      /; s/ *<class.*//' \
        | head -3
else
    warn "no HID digitizer found — hardware-dependent behaviour cannot be verified"
    printf '      Check the USB-C cable carries data, not just power.\n'
fi

printf '\n  Displays:\n'
if [ -x .build/debug/m14ttouch ]; then
    .build/debug/m14ttouch --list 2>/dev/null | sed 's/^/  /'
else
    printf '    (build first)\n'
fi

head_ "Permissions (grant in System Settings → Privacy & Security)"
printf '  Input Monitoring  — required to read raw HID touch data\n'
printf '  Accessibility     — required to post cursor/click events\n'
printf '  Status is per-binary and cannot be read reliably from a script;\n'
printf '  check the panes directly if touch input does nothing.\n'

if [ "$FAILED" -eq 0 ]; then
    printf '\n\033[32mEnvironment OK.\033[0m\n'
else
    printf '\n\033[31mEnvironment incomplete — see ✘ above.\033[0m\n'
fi
exit "$FAILED"
