# Signing, Gatekeeper and notarization

Where this project actually stands, measured on 2026-09-12 against the app
installed by `brew install --cask m14t-touch`. Nothing here is a plan; the plan
is the last section.

## What is signed, and with what

Every build is signed. `scripts/package-app.sh` picks the best identity it can
find, in this order: a Developer ID, then a local self-signed certificate, then
ad-hoc. On this machine it finds the second one.

```
$ codesign -dv --verbose=4 "/Applications/M14t Touch.app"
Identifier=com.m14ttouch.app
Format=app bundle with Mach-O universal (x86_64 arm64)
CodeDirectory v=20400 size=3050 flags=0x0(none) hashes=89+3 location=embedded
Authority=M14t Touch Local
Signed Time=12 Sep 2026 at 15:07:11
TeamIdentifier=not set
Sealed Resources version=2 rules=13 files=1
```

`TeamIdentifier=not set` is the whole story in one line: the certificate is
self-signed, issued by `scripts/make-signing-identity.sh` into this Mac's login
keychain, and belongs to no Apple Developer team.

## codesign: passes

```
$ codesign --verify --deep --strict --verbose=2 "/Applications/M14t Touch.app"
/Applications/M14t Touch.app: valid on disk
/Applications/M14t Touch.app: satisfies its Designated Requirement
```

The signature is structurally sound and the bundle is sealed. This is also what
makes permissions survive an upgrade, because the requirement macOS records
when Input Monitoring is granted is:

```
designated => identifier "com.m14ttouch.app"
              and certificate leaf = H"a1df0dd75f8c7994e6d02b76d3cd38bceec13272"
```

Every release signed with that same certificate satisfies it, so the grant
carries across rebuilds, upgrades, and a move from `~/Applications` to
`/Applications` — verified by installing over a running copy and watching the
new one seize the HID device with nothing re-granted.

## spctl: rejected

```
$ spctl -a -vv "/Applications/M14t Touch.app"
/Applications/M14t Touch.app: rejected
origin=M14t Touch Local
```

Gatekeeper assesses whether Apple has seen this software. It has not. No amount
of local signing changes that answer; only notarization does.

## What quarantine does with that

Anything downloaded carries `com.apple.quarantine`. macOS refuses to launch
unnotarized code that carries it — measured across three signature kinds, which
is worth restating because it is the thing people guess wrong: an ad-hoc build,
a self-signed build and a build signed by an untrusted certificate are killed
identically, and all three run once the attribute is removed. **The signature is
not what decides; the attribute is.**

So the manual path is a disk image plus one of:

- System Settings → Privacy & Security → **Open Anyway**, after the first refusal
- `xattr -dr com.apple.quarantine "/Applications/M14t Touch.app"`

## Why the Homebrew install needs a workaround

Homebrew 6 applies quarantine on download, unconditionally — `Cask::Download`
calls `quarantine(downloaded_path)` with nothing to skip it, and the
`--no-quarantine` flag that used to opt out has been removed. Installed as-is,
the cask would put a working app in `/Applications` that cannot open.

The cask therefore clears the attribute in a `postflight_steps` stanza, and says
so in its caveats rather than doing it quietly. What Gatekeeper would have
guaranteed — that the bytes are the ones the developer published — the cask
guarantees differently: a SHA-256 pinned in the tap, over HTTPS, from this
project's own release. That is a smaller guarantee. It is not nothing, and it is
stated where a user will read it.

**This is a workaround, and it is the reason the cask cannot go into the
official homebrew-cask repository**, which requires that a cask "must not
require … Gatekeeper to be disabled or bypassed".

## What changes with a Developer ID and notarization

- `spctl` accepts. The app opens on any Mac, downloaded from anywhere, with no
  dialog and no Terminal.
- The cask's `postflight_steps` stanza comes out, and with it the one thing in
  this project that steps around a macOS security check.
- The disk image can be stapled, so it also works on a Mac that is offline.
- One barrier to homebrew-cask is removed. Three remain, and none of them are
  technical — see `OFFICIAL-CASK.md` in the tap.
- Permissions: **the certificate changes, so the designated requirement changes,
  so every existing user grants Input Monitoring and Accessibility once more.**
  This happens exactly once, on the first notarized release, and it should be
  said plainly in that release's notes.

## The steps, when there is $99 to spend

1. Enrol in the Apple Developer Program ($99/year).
2. In Xcode → Settings → Accounts, or from the developer portal, create a
   **Developer ID Application** certificate and let it land in the login
   keychain.
3. Create an app-specific password at appleid.apple.com, then store the notary
   credentials once:

   ```sh
   xcrun notarytool store-credentials m14ttouch \
       --apple-id <apple id> --team-id <team> --password <app-specific password>
   ```

4. Run `./scripts/make-dmg.sh`. Nothing else needs editing.

## What the scripts already do

They are written for this and have been since before there was a certificate to
test them with:

- `scripts/package-app.sh` prefers a `Developer ID Application` identity over
  the local one, and when it finds one it signs with `--options runtime
  --timestamp`. The hardened runtime is required for notarization and costs
  nothing here: nothing in this app injects, and its one private symbol is
  resolved from a system framework, which the hardened runtime allows.
- `scripts/make-dmg.sh` notices a Developer ID signature, submits the image with
  `xcrun notarytool submit --wait`, staples it with `xcrun stapler staple`, and
  says which of the two first-run notes to send depending on whether stapling
  succeeded. Credentials come from a keychain profile, so no secret goes near
  the repository or a shell history.

What is missing is the certificate, not the code.
