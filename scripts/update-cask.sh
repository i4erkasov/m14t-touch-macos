#!/usr/bin/env bash
#
# update-cask.sh — point the Homebrew cask at a published release.
#
#   scripts/update-cask.sh v1.0.4 /path/to/homebrew-m14t-touch
#
# Runs in CI, from .github/workflows/release.yml, and runs the same way on a Mac
# — which is the point of it being a script rather than twenty lines of YAML.
# What it must never do is guess: the checksum is of the file GitHub is serving,
# downloaded here, not of whatever build happens to be in ./build.
#
# It rewrites exactly two lines. The url is built from `version`, so it follows
# along; if the release ever stops matching that url, this stops rather than
# committing a cask that resolves to a 404.

set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/version.sh

TAG="${1:-}"
TAP_DIR="${2:-}"
CASK_RELATIVE="${CASK_PATH:-Casks/m14t-touch.rb}"
REPO="${GITHUB_REPOSITORY:-i4erkasov/m14t-touch-macos}"

usage() { echo "usage: $0 <tag, e.g. v1.0.4> <path to tap checkout>" >&2; exit 2; }
[ -n "$TAG" ] && [ -n "$TAP_DIR" ] || usage

case "$TAG" in
    v[0-9]*) ;;
    *) echo "❌ '$TAG' is not a release tag of the form vX.Y.Z" >&2; exit 1 ;;
esac
if ! version_is_release "$TAG"; then
    echo "❌ '$TAG' looks like a development build, not a release" >&2
    exit 1
fi

VERSION="$(version_bundle "$TAG")"
ASSET="M14t-Touch-${TAG}.dmg"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

CASK="$TAP_DIR/$CASK_RELATIVE"
[ -f "$CASK" ] || { echo "❌ no cask at $CASK" >&2; exit 1; }

# The url in the cask is a template. Render it the way Homebrew will, and check
# it lands on the file we are about to checksum — otherwise the asset naming has
# changed and a human needs to look at the url stanza.
TEMPLATE="$(sed -n 's/^ *url "\(.*\)".*/\1/p' "$CASK" | head -1)"
[ -n "$TEMPLATE" ] || { echo "❌ no url stanza in $CASK" >&2; exit 1; }
RENDERED="${TEMPLATE//\#\{version\}/$VERSION}"
if [ "$RENDERED" != "$URL" ]; then
    echo "❌ the cask's url does not describe this release." >&2
    echo "   cask renders: $RENDERED" >&2
    echo "   release is:   $URL" >&2
    echo "   Fix the url stanza by hand; this script only moves version and sha256." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Fetching $URL"
curl --fail --silent --show-error --location --retry 3 --output "$WORK/$ASSET" "$URL"

BYTES="$(wc -c < "$WORK/$ASSET" | tr -d ' ')"
if [ "$BYTES" -lt 100000 ]; then
    echo "❌ $ASSET is only $BYTES bytes — that is not a disk image" >&2
    exit 1
fi
# A UDIF image ends with a 512-byte trailer that starts with "koly". Cheaper
# than mounting it, works on a Linux runner, and catches an HTML error page
# served with a 200.
if [ "$(tail -c 512 "$WORK/$ASSET" | head -c 4)" != "koly" ]; then
    echo "❌ $ASSET does not end in a UDIF trailer — not a disk image" >&2
    exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
    SHA="$(sha256sum "$WORK/$ASSET" | cut -d' ' -f1)"
else
    SHA="$(shasum -a 256 "$WORK/$ASSET" | cut -d' ' -f1)"
fi
echo "    $ASSET: $BYTES bytes, sha256 $SHA"

VERSION="$VERSION" SHA="$SHA" CASK="$CASK" python3 - <<'PY'
import os, re, sys

path, version, sha = os.environ["CASK"], os.environ["VERSION"], os.environ["SHA"]
text = original = open(path, encoding="utf-8").read()

for name, value in (("version", version), ("sha256", sha)):
    text, count = re.subn(rf'^(\s*{name}\s+)"[^"]*"', rf'\g<1>"{value}"',
                          text, count=1, flags=re.M)
    if count != 1:
        sys.exit(f"no {name} stanza in {path}")

if text == original:
    print("==> The cask already says this. Nothing to change.")
else:
    open(path, "w", encoding="utf-8").write(text)
    print("==> Updated the cask.")
PY

cd "$TAP_DIR"
if git diff --quiet -- "$CASK_RELATIVE"; then
    echo "changed=no"
    exit 0
fi

# Only those two lines, and this is where that is enforced rather than assumed.
CHANGED="$(git diff --numstat -- "$CASK_RELATIVE" | awk '{print $1}')"
if [ "${CHANGED:-0}" -gt 2 ]; then
    echo "❌ $CHANGED lines changed; expected at most 2 (version, sha256)" >&2
    git diff -- "$CASK_RELATIVE" >&2
    exit 1
fi
git --no-pager diff -- "$CASK_RELATIVE"
echo "changed=yes"
