#!/usr/bin/env bash
#
# version.sh — the one place a version string is decided.
#
# There are two forms and they are not interchangeable:
#
#   version_tag     v1.0.4   what the git tag and the GitHub release are called,
#                            and therefore what the DMG asset is named and what
#                            the Homebrew cask's `url` interpolates.
#
#   version_bundle  1.0.4    what goes in Info.plist. CFBundleShortVersionString
#                            is meant to be a plain version; the "v" is a git
#                            convention that had leaked into the bundle, leaving
#                            the app claiming "v1.0.3" while the cask that
#                            installed it said "1.0.3".
#
# Source this rather than repeating `git describe`: two copies of that line is
# how the two forms drifted apart in the first place.

# The tag form, exactly as git sees the tree. A development build carries what
# `git describe` appends — "-6-gf0f66b5" past the tag, "-dirty" for uncommitted
# changes — because a build that is not a release must not claim to be one.
version_tag() {
    git describe --tags --always --dirty 2>/dev/null || echo "0.0.0-dev"
}

# The bundle form: the tag with its leading "v" removed, and nothing else
# changed. A development build keeps its suffix — Version.swift parses it, and
# the update check needs it to know the build is *ahead* of the last release.
version_bundle() {
    local tag="${1:-$(version_tag)}"
    printf '%s' "${tag#v}"
}

# Whether this tree is exactly a tag: no commits past it, nothing uncommitted.
version_is_release() {
    case "${1:-$(version_tag)}" in
        *-dirty) return 1 ;;
        *-g*)    return 1 ;;
        v[0-9]*|[0-9]*) return 0 ;;
        *)       return 1 ;;
    esac
}

# Read the version back out of a built bundle and refuse to ship a wrong one.
#
# Checked against the artifact rather than against the variable that was meant
# to produce it, because the failure being guarded here — a "v" reaching
# Info.plist — happened through a template, not through arithmetic.
assert_bundle_version() {
    local app="$1" expected="$2" plist="$1/Contents/Info.plist" key value
    [ -f "$plist" ] || { echo "❌ no Info.plist at $plist" >&2; return 1; }

    for key in CFBundleShortVersionString CFBundleVersion; do
        value="$(plutil -extract "$key" raw "$plist" 2>/dev/null || true)"
        if [ -z "$value" ]; then
            echo "❌ $key is missing from the bundle" >&2
            return 1
        fi
        case "$value" in
            v*|V*)
                echo "❌ $key is \"$value\" — the \"v\" belongs to the git tag," >&2
                echo "   not to the bundle. See scripts/version.sh." >&2
                return 1
                ;;
        esac
        if [ "$value" != "$expected" ]; then
            echo "❌ $key is \"$value\", expected \"$expected\"" >&2
            return 1
        fi
    done
    return 0
}
