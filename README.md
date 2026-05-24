# Lenovo ThinkVision M14t display touch driver for macOS

> A tiny, dependency-free macOS driver that brings touchscreen input to the
> **Lenovo ThinkVision M14t** when connected to a Mac over USB-C.

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

macOS recognises the M14t as an external display but silently ignores its USB
HID touch interface — so the screen works, but touch does nothing. The usual fix
is commercial drivers that costs **~$171** for a single license. This is
a focused open-source alternative that does one thing well: **turns a finger
touch into a mouse click**, entirely in user space using Apple's public APIs.

No kernel extension. No system extension. No paid license. ~600 lines of Swift.

---

## How it works

The M14t multiplexes two independent interfaces over the single USB-C cable:

```
USB-C cable
├── DisplayPort Alt Mode  →  video    →  handled natively by macOS ✅
└── USB HID Digitizer      →  touch    →  ignored by macOS, handled here ✅
```

The driver reads the HID digitizer stream and converts it to cursor events:

```
 ┌──────────────┐   raw X / Y / TipSwitch   ┌────────────────────┐
 │  M14t panel  │ ─────────────────────────▶│   HIDTouchDriver   │
 └──────────────┘     (IOHIDManager)         └─────────┬──────────┘
                                                       │
                          calibrated raw → screen px   │
                                            ┌──────────▼──────────┐
                                            │  CoordinateMapper    │  (pure, tested)
                                            └──────────┬──────────┘
                                                       │  CGPoint
                                            ┌──────────▼──────────┐
                                            │    MouseEmitter      │
                                            └──────────┬──────────┘
                                                       │  CGEvent
                                                       ▼
                                              macOS cursor / click
```

**Touch model** — a single contact maps directly to the left mouse button:

| Gesture | macOS event |
|---|---|
| Finger down | `leftMouseDown` |
| Finger moves while down | `leftMouseDragged` |
| Finger up | `leftMouseUp` |

A down-then-up without movement is a **click**; a down-move-up is a **drag**.
That's the whole contract — deliberately simple and reliable.

---

## Project layout

The code is split by responsibility so each piece is small and, where it
matters, unit-testable:

| File | Responsibility |
|---|---|
| `main.swift` | Entry point: dispatch, permissions, run loop |
| `ArgumentParser.swift` | Pure CLI parsing → `TouchConfig` |
| `TouchConfig.swift` | Runtime options value type |
| `HIDTouchDriver.swift` | IOKit orchestration + touch state machine |
| `CoordinateMapper.swift` | **Pure** raw→screen math (fully tested) |
| `Calibration.swift` | Calibration model + JSON persistence |
| `DisplayResolver.swift` | Display enumeration and selection |
| `MouseEmitter.swift` | `CGEvent` posting |
| `HIDUsage.swift` | Named HID usage constants |

The mapping math and argument parsing have no hardware or global-state
dependencies, so they're covered by `swift test` without a connected device.

---

## Requirements

- macOS 13 (Ventura) or later — Intel or Apple Silicon
- Xcode Command Line Tools: `xcode-select --install`
- The M14t connected via a **data-capable** USB-C cable

---

## Quick start

```bash
git clone https://github.com/talesmousinho/m14t-touch-macos.git
cd m14t-touch-macos

# 1. Build
swift build -c release

# 2. Find which display index is your M14t
.build/release/m14ttouch --list

# 3. Calibrate once — touch all four corners firmly
.build/release/m14ttouch --display 1 --auto-calibrate

# 4. From now on, just run (calibration is remembered)
.build/release/m14ttouch --display 1
```

Or use the helper script, which builds and runs calibration interactively in the
terminal. Touch all four corners, then press Enter; the installer stops
calibration and returns the prompt. With `--autostart`, the driver then runs
silently via LaunchAgent, discards normal output, and writes errors to
`/tmp/m14ttouch.err.log`. The script installs the driver at
`~/.local/bin/m14ttouch` so macOS permissions keep pointing at a stable path:

```bash
./install.sh              # build + calibrate
./install.sh --autostart  # build + calibrate + run automatically at login
```

---

## Permissions

macOS gates the two things this driver needs. Grant both once:

| Permission | Why | Where |
|---|---|---|
| **Input Monitoring** | Read raw HID touch data | System Settings → Privacy & Security → Input Monitoring |
| **Accessibility** | Post cursor / click events | System Settings → Privacy & Security → Accessibility |

Add your terminal app for interactive runs, and add `~/.local/bin/m14ttouch` for
LaunchAgent/autostart runs. If `m14ttouch` is already listed but autostart still
fails, remove that entry and add `~/.local/bin/m14ttouch` again, then restart the
existing LaunchAgent with:

```bash
launchctl kickstart -k "gui/$(id -u)/com.talesfonseca.m14ttouch"
```

The driver prompts for Accessibility automatically on first interactive run.

---

## Calibration

The M14t's HID descriptor advertises a `0–32767` coordinate range but only
emits values in a much narrower band — so a naive mapping puts touches in the
wrong place. `--auto-calibrate` solves this by widening its known range as you
touch, then saving the result to `~/.m14ttouch.json`:

```json
{
  "xMax" : 12371,
  "xMin" : 1,
  "yMax" : 6959,
  "yMin" : 1
}
```

Subsequent launches load this automatically. If something changes:

```bash
m14ttouch --reset-calibration                 # wipe and start over
m14ttouch --display 1 --x-min 1 --x-max 12371 --y-min 1 --y-max 6959  # set by hand
m14ttouch --display 1 --invert-y              # fix a flipped axis
```

---

## All options

```
--display N          Display index the M14t is mapped to (default: 1)
--auto-calibrate     Learn the touch range, then persist it
--invert-x           Mirror the horizontal axis
--invert-y           Mirror the vertical axis
--x-min / --x-max    Manual raw X bounds (override saved calibration)
--y-min / --y-max    Manual raw Y bounds
--debug              Print every HID event and resulting action
--no-accessibility-prompt
                     Suppress the Accessibility prompt for LaunchAgents
--list               List connected displays and exit
--reset-calibration  Delete saved calibration and exit
--help, -h           Show help
```

---

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
| No device detected | Replug USB-C; confirm the cable carries data, not just power; try `--debug` |
| Touch offset / wrong place | Re-run `--auto-calibrate` and touch all four corners |
| Vertically/horizontally flipped | Add `--invert-y` and/or `--invert-x` |
| Cursor doesn't move at all | Grant **Accessibility** permission |
| `--debug` shows nothing | Grant **Input Monitoring** permission |
| Accessibility prompt repeats | Re-run `./install.sh --autostart`; the LaunchAgent should use `--no-accessibility-prompt` |
| Autostart installs but driver is not running | Remove/re-add **Accessibility** for `~/.local/bin/m14ttouch`, then run `launchctl kickstart -k "gui/$(id -u)/com.talesfonseca.m14ttouch"` |
| Works in Terminal, stops after closing it | Use `./install.sh --autostart` |

---

## Scope & roadmap

This release is intentionally **single-touch only** — one contact, one cursor —
because that's the case that's robust across apps. Multi-finger gestures
(two-finger scroll, right-click) are a natural next step but require frame-based
contact tracking and are out of scope for v1.

- [x] Single-touch → click / drag
- [x] Auto-calibration with persistence
- [x] Multi-display support, axis inversion
- [x] Unit-tested coordinate mapping
- [ ] Two-finger scroll
- [ ] Two-finger tap → right-click
- [ ] Menu-bar status app

---

## Why this exists

Built to avoid a $171 license for a feature that's really just "read HID, post
CGEvent." It's also a compact example of bridging a raw USB HID device to the
macOS event system in pure Swift — calibration, coordinate mapping, IOKit
callbacks, and synthetic input, with the tricky math isolated and tested.

## License

[MIT](LICENSE) — do whatever you want with it.
