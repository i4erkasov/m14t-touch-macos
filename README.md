# Lenovo ThinkVision M14t display touch driver for macOS

> A tiny, dependency-free macOS driver that brings touchscreen input to the
> **Lenovo ThinkVision M14t** when connected to a Mac over USB-C.

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

macOS recognises the M14t as an external display but silently ignores its USB
HID touch interface — so the screen works, but touch does nothing. The usual fix
is a commercial driver costing **~$171** for a single licence. This is a focused
open-source alternative: **tap to click, swipe to scroll, press and hold to
drag**, in user space, from a menu-bar app.

No kernel extension. No system extension. No paid licence.

One private API is used, for one thing only — hiding the pointer while a finger
is on the panel, which no public API can do from a background process. It is off
by default, confined to a single file, and the driver runs without it.

---

## How it works

The M14t multiplexes two independent interfaces over the single USB-C cable:

```
USB-C cable
├── DisplayPort Alt Mode  →  video  →  handled natively by macOS
└── USB HID Digitizer     →  touch  →  ignored by macOS, handled here
```

There are two ways to read a touch, and you choose between them:

**Touchscreen mode** treats the panel as a touchscreen. A tap clicks where you
tapped, a swipe scrolls, and pressing and holding starts a drag. The pointer
does not chase your finger: it is placed once, where the gesture begins, and
left there.

| Gesture | Result |
|---|---|
| Short tap | Click at the point touched |
| Swipe | Scroll, with the pointer stationary |
| Press, hold, then move | Drag |

**Mouse mode** is the original behaviour, kept as the compatibility fallback: a
contact presses the left button, movement drags it, release releases it.


## Project layout

Split by responsibility, so each piece is small and — where it matters — testable
without a panel attached.

```
Sources/M14tTouch/
├── main.swift                 entry point; picks CLI or app
├── App/                       menu bar, settings window
├── CLI/                       argument parsing, runtime options
└── Core/
    ├── TouchEngine.swift      pumps frames from recognizer into emitter
    ├── HID/                   IOKit, usage constants, TouchPoint/TouchFrame
    ├── Display/               display identity, selection, coordinate mapping
    ├── Calibration/           persistence, precedence, auto-calibration
    ├── Gestures/              recognizers and their vocabulary
    ├── Events/                emission into macOS
    ├── Cursor/                pointer visibility
    ├── Permissions/           Input Monitoring and Accessibility status
    └── Settings/              stored preferences
```

The pipeline:

```
IOHIDManager -> HIDTouchDriver -> TouchFrame -> GestureRecognizer -> InputAction -> EventEmitter -> CGEvent
                (IOKit only)                    (what the finger meant)            (how macOS is told)
```

Gesture recognition sees nothing but frames and produces nothing but actions —
no IOKit, no CoreGraphics, no calibration — which is why the tricky parts are
covered by `swift test` with no hardware.

---

## Requirements

- macOS 13 (Ventura) or later — Intel or Apple Silicon
- Full Xcode to run the tests. `swift build` works with Command Line Tools alone,
  but XCTest does not ship with them
- The M14t connected with a **data-capable** USB-C cable

---

## Quick start

### As an application

```bash
git clone https://github.com/i4erkasov/m14t-touch-macos.git
cd m14t-touch-macos

./scripts/package-app.sh
cp -R "build/M14t Touch.app" ~/Applications/
open ~/Applications/"M14t Touch.app"
```

Copy it somewhere permanent before granting permissions — see below for why.

It lives in the menu bar. The first launch will look broken: the status says no
touch device even though the panel is plugged in, because reading the HID stream
needs a permission it does not have yet. Open **Settings… → General →
Permissions** and grant both.

### From the terminal

The command-line build is the same binary and is the better one to develop
against, since it keeps its permissions across rebuilds.

```bash
swift build -c release

.build/release/m14ttouch --list                    # which displays are connected
.build/release/m14ttouch --auto-calibrate          # touch all four corners
.build/release/m14ttouch --mode touchscreen        # tap, scroll, long-press drag
```

Without `--display`, the first external display is used.

---
## The stylus

The pen hovers, clicks, drags and reports pressure. Hovering moves the pointer
to where the pen is **on the panel** — which sounds unremarkable until you know
what happens without this driver.

macOS handles the M14t's pen itself, and handles it as a relative pointing
device: hovering over the panel drags the pointer around whichever screen it was
already on, usually the built-in one. It cannot be corrected by adding absolute
positioning alongside, because the two would fight. So the driver takes the
device exclusively.

**That trade is worth knowing.** While the driver runs, the pen is accurate.
While it does not, **the pen does nothing at all** — where before it did
something wrong. `--no-pen` gives the device back if you would rather have the
old behaviour.

What the hardware turned out to do, all of it measured rather than assumed
(`M14t_PEN_CAPABILITIES.md`):

| | |
|---|---|
| Hover, proximity, tip, pressure | yes |
| Buttons | two, and both work while hovering |
| The button nearest the tip | an **eraser**, not a button — hold it and the panel reports an eraser stroke instead of a tip one |
| The far button | free to be mapped; not mapped yet |
| Tilt | declared by the descriptor, never sent |

Two things follow that are worth expecting rather than discovering:

- **A click needs a firm press.** The tip switch fires around 58% of the
  pressure range, so a light or angled tap may not register. This is the pen,
  not the driver — contacts arrive cleanly, with no chatter.
- **The eraser does nothing yet.** Mapping it, and the far button, to actions is
  the next piece of work; guessing that an eraser stroke means a left click
  would be worse than waiting.

---


## Permissions

macOS gates the two things this driver needs:

| Permission | Why |
|---|---|
| **Input Monitoring** | Reads the raw HID touch stream |
| **Accessibility** | Posts pointer, click and scroll events |

The app shows both under **Settings… → General → Permissions**, with a button
that opens the right pane. It re-checks whenever you come back to it, so the
status updates without a restart.

**They are granted per binary, not per project.** The app and the command-line
build are separate as far as macOS is concerned, and granting one does nothing
for the other. Two consequences worth knowing before they waste your time:

- **Copy the app somewhere permanent before granting.** Permission follows the
  path, so an app granted in `build/` loses it on the next rebuild.
- **Rebuilding can revoke it.** The bundle is signed ad-hoc, so its signature
  changes with the binary and macOS may treat the rebuilt app as a stranger. If
  the app stops working after a rebuild, remove it from both panes and add it
  again. This is why development is better done against the command-line build,
  which keeps its grants.


## Calibration

The panel reports a narrower coordinate range than its HID descriptor claims, so
a naive mapping puts touches in the wrong place. `--auto-calibrate` widens its
known range as you touch and saves the result to `~/.m14ttouch.json`:

```json
{ "xMin": 1, "xMax": 12302, "yMin": 108, "yMax": 6959 }
```

Touch **all four corners** — nothing is saved until both axes have spread, so
covering only one direction produces no calibration at all.

Subsequent launches load it automatically. Precedence is **manual flags > saved
file > what the descriptor claims**, and the descriptor is the least trustworthy
of the three: this panel presents two interfaces, and one of them advertises a
range it never reports.

```bash
m14ttouch --reset-calibration                              # start over
m14ttouch --x-min 1 --x-max 12302 --y-min 108 --y-max 6959 # set by hand
```

### From the app

**Calibrate…**, in the menu or the settings window, covers the panel and shows
four targets to touch. It then asks whether a dot follows your finger, and its
buttons are pressed *through the calibration being tested* — so hitting **Keep
it** is itself the proof that it worked. Escape cancels and keeps whatever was
there before.

It also works out which way the panel counts, so a mirrored axis is corrected
without anyone having to find the checkbox.

Calibration is stored per display, so a panel is recognised again after
replugging and a second one does not overwrite the first.


## All options

Run `m14ttouch --help` for the current list. The ones worth knowing:

```
--app                  Run as a menu-bar application
--mode MODE            mouse (default) or touchscreen
--display N            Display index; without it, the first external one
--auto-calibrate       Learn the touch range, then persist it
--list                 List connected displays and exit
--reset-calibration    Delete saved calibration and exit

Touchscreen gestures
--no-tap                 A short touch does not click
--no-one-finger-scroll   A swipe does nothing rather than scrolling
--no-long-press-drag     Holding still stays a tap
--scroll-threshold N     Movement that commits to scrolling (default: 10 px)
--scroll-sensitivity N   Multiplier for scroll deltas (default: 1.0)
--no-natural-scroll      Invert the scroll direction
--long-press MS          Hold before a contact becomes a drag (default: 400)

Pointer
--hide-cursor MODE       never (default), scrolling, or touching
--no-restore-cursor      Leave the pointer where the gesture took it

Diagnostics
--debug                Print every HID event and resulting action
--invert-x, --invert-y Mirror an axis
--x-min / --x-max      Manual raw bounds, overriding saved calibration
--y-min / --y-max
```

Anything set in the app's settings window is remembered; command-line flags
override the stored value for that run.


## Testing

```bash
swift test
```

Covers the coordinate mapping (corners, center, clamping, axis inversion,
multi-display offsets, degenerate input) and CLI parsing.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No device detected | Replug the USB-C cable and confirm it carries data, not just power. `--debug` prints every HID event |
| The app says no device, the terminal build works | Input Monitoring is granted to one binary and not the other — see Permissions |
| It worked, then stopped after a rebuild | The ad-hoc signature changed; remove and re-add the app in both permission panes |
| Touch lands in the wrong place | Run `--auto-calibrate` and touch all four corners. If it is inverted, use `--invert-x` / `--invert-y` or the Calibration tab |
| Touch lands on the wrong screen | Pick the display in **Settings… → General**, or pass `--display N` |
| Nothing moves at all | Accessibility is missing |
| The pointer stays hidden | Only possible with `--hide-cursor`. Quitting restores it; `killall m14ttouch` does not, so quit from the menu |
| A swipe does nothing | One-finger scroll is switched off — that setting means exactly this |


## Scope & roadmap

- [x] Single-touch → click / drag (mouse mode)
- [x] Tap to click, one-finger scroll, long press to drag (touchscreen mode)
- [x] Auto-calibration with persistence
- [x] Display chosen by identity, so replugging finds it again
- [x] Menu-bar app with a settings window
- [x] Optional pointer hiding and restoring
- [x] Guided calibration on the panel itself
- [ ] Start at login, reconnect handling
- [ ] Diagnostics: raw HID viewer, device info
- [x] Stylus: hover, tip, pressure, absolute positioning on the panel
- [ ] Stylus: button and eraser actions, pressure to applications
- [ ] Two-finger scroll and right-click

Multi-touch is not implemented: everything above is one contact. What it would
take, and why pinch-to-zoom is harder than it looks, is written up in
`docs/pinch-and-multitouch.md`.


## Why this exists

Built to avoid a $171 license for a feature that's really just "read HID, post
CGEvent." It's also a compact example of bridging a raw USB HID device to the
macOS event system in pure Swift — calibration, coordinate mapping, IOKit
callbacks, and synthetic input, with the tricky math isolated and tested.

## License

[MIT](LICENSE) — do whatever you want with it.
