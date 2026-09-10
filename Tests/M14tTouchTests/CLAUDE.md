# CLAUDE.md

Guidance for AI agents working in this repository.

## What this is

`m14ttouch` — a userspace macOS touch driver for the **Lenovo ThinkVision M14t**.
Reads the monitor's USB HID digitizer via `IOHIDManager` and posts synthetic
`CGEvent`s. No kernel/system extension, no third-party dependencies.

This repo is a **fork** of `talesmousinho/m14t-touch-macos` (remote: `upstream`),
currently identical to it at commit `bb2294f`.

The goal of the fork is defined in **`M14t_Touch_Manager_TZ.md`** — the spec.
It turns the current "finger drags the mouse cursor" CLI into a proper
touchscreen translation layer with a SwiftUI menu-bar app.
**Read the spec before any non-trivial change.** Key sections:

| Section | Topic |
|---|---|
| §4–6 | Target architecture, `TouchPoint` / `TouchFrame` / `InputAction` |
| §7–10 | Touchscreen mode: tap, one-finger scroll, long-press drag, cursor policy |
| §22 | Gesture state machine (incl. the scroll/drag gesture lock) |
| §27 | Required unit tests |
| §28 | Version plan v0.1 → v1.0 |
| §32 | Coding requirements (hard rules, see below) |
| §33–34 | Agent workflow and the first assigned task |

## Commands

```bash
swift build                 # debug build
swift build -c release      # release build → .build/release/m14ttouch
swift test                  # unit tests — REQUIRES full Xcode, see below
./scripts/verify-env.sh     # check the toolchain is set up correctly
./scripts/package-app.sh    # assemble build/M14t Touch.app
```

One binary, two shapes. A bare executable is the CLI; the same binary inside the
bundle is the menu-bar app, decided by whether `Bundle.main.bundleIdentifier`
matches the app's. `--app` forces the app shape from a terminal.

**Develop against the CLI.** Input Monitoring and Accessibility are granted per
binary, so the bundle is a separate identity from the terminal and needs its own
grants — and an ad-hoc signature changes on every build, so a rebuilt bundle can
look like a new, unpermitted application. `--app` gets the menu bar with the
terminal's existing grants.

Running the driver needs a connected M14t plus two macOS permissions
(Input Monitoring, Accessibility), so it generally cannot be verified from an
agent session — see "Hardware" below.

```bash
.build/debug/m14ttouch --list     # list displays (works without the M14t)
.build/debug/m14ttouch --help
```

## Environment constraints

**`swift test` requires full Xcode, not just Command Line Tools.** XCTest is not
shipped in CLT, so with CLT alone the test target fails to compile with
`no such module 'XCTest'` while `swift build` still succeeds. If tests fail that
way, run `./scripts/verify-env.sh` — do not "fix" it by deleting or rewriting
tests. Full Xcode is required regardless for the SwiftUI `.app` bundle
(spec §13) and `SMAppService` (§20).

**Do not assume the M14t is plugged in, and do not assume it is absent** — check
with `./scripts/verify-env.sh`. All core logic must be testable without it
(spec §32), which is why `CoordinateMapper` and the recognizers are pure value
types. Behaviour that genuinely requires the panel must be reported as
unverified, not assumed to work.

Note that `system_profiler SPUSBDataType` returns nothing at all on macOS 26
even with devices attached; use `ioreg` to look for hardware.

**Do not guess HID usages.** If a usage is unknown, add diagnostics to capture it
from a real device first (spec §33.7, §18).

## Architecture

v0.1 is complete — the pipeline spec §4 describes is in place:

```
IOHIDManager -> HIDTouchDriver -> TouchFrame -> GestureRecognizer -> InputAction -> EventEmitter -> CGEvent
                (IOKit only)                   (MouseModeRecognizer)               (MouseEventEmitter)
                                               `-- pure, no hardware needed --'
```

| Path | Responsibility |
|---|---|
| `main.swift` | Composition root: dispatch, mode selection, permissions, run loop |
| `CLI/ArgumentParser.swift` | Pure CLI parsing -> `TouchConfig` |
| `CLI/TouchConfig.swift` | Runtime options value type |
| `Core/TouchEngine.swift` | Pumps frames from recognizer into emitter |
| `Core/HID/HIDTouchDriver.swift` | IOKit only: opens the device, builds frames |
| `Core/HID/TouchPoint.swift` | `TouchPoint` + `TouchFrame` |
| `Core/HID/HIDUsage.swift` | Named HID usage constants |
| `Core/Display/CoordinateMapper.swift` | **Pure** raw->screen math |
| `Core/Display/DisplayResolver.swift` | `CGGetActiveDisplayList` wrapper |
| `Core/Calibration/Calibration.swift` | `CalibrationData` + injectable JSON store |
| `Core/Calibration/CalibrationController.swift` | Precedence and auto-calibration |
| `Core/Gestures/TouchMode.swift` | Mode -> recognizer factory |
| `Core/Gestures/GestureConfiguration.swift` | Thresholds, delays, sensitivity |
| `Core/Gestures/MouseModeRecognizer.swift` | The original touch model, as a recognizer |
| `Core/Gestures/TouchscreenRecognizer.swift` | Tap, one-finger scroll, long-press drag |
| `Core/Events/RoutingEventEmitter.swift` | Sends each action to the emitter that builds it |
| `Core/Events/MouseEventEmitter.swift` | `InputAction` -> `CGEventType`, cursor parking |
| `Core/Events/ScrollEventEmitter.swift` | Pixel-unit scroll wheel events |
| `Core/Events/CGEventPoster.swift` | `CGEvent` posting |
| `Core/Cursor/CursorVisibilityController.swift` | Balances hide/show for finger and pen |
| `Core/Pen/PenRecognizer.swift` | Raw pen samples -> `PenAction` |
| `Core/Pen/PenMouseBackend.swift` | `PenAction` -> mouse events |
| `App/PenPointerOverlay.swift` | The dot drawn in place of the arrow |
| `Core/Diagnostics/Log.swift` | stdout *and* the unified log, for the bundle |

Keep these layers separate: HID acquisition, mapping, calibration, gesture
recognition, event emission, UI, persistence.

**Adding a gesture mode** means writing a `GestureRecognizer` and returning it
from `TouchMode.makeRecognizer`. Nothing else should need to change — that is how
touchscreen mode was added in v0.2.

**Two things public APIs cannot do**, both established by measurement rather than
assumption, and both worth knowing before promising them:

- *Scroll without moving the cursor.* A scroll event has no destination; setting
  `CGEvent.location` on one warps the pointer instead of addressing it, and
  posting to the owning process leaves the cursor alone but scrolls nothing. So
  the cursor is placed on the target once per gesture and restored afterwards.
- *Hide the cursor.* `NSCursor.hide` and `CGDisplayHideCursor` act only while the
  calling app is frontmost, which never happens here. Doing it from the
  background needs a private API, which the spec amendment now permits **for
  this and nothing else** — see the hard rules. It is quarantined in
  `Core/Cursor/PrivateCursorVisibility.swift`, resolved through `dlsym` so a
  missing symbol degrades instead of failing to launch, and a single hide only
  blinks: the window server drops it the moment the pointer moves, so it must be
  re-asserted every frame.
- *Replace another application's cursor image.* `NSCursor` applies only over the
  setting application's own windows while it is frontmost. The pen's dot is
  therefore drawn in an overlay window (`App/PenPointerOverlay.swift`) with the
  arrow hidden underneath, not by changing the system cursor.

Calibration precedence: manual flags > saved `~/.m14ttouch.json` > HID descriptor.

## Investigated, not built

- `docs/pinch-and-multitouch.md` — whether pinch-to-zoom is possible (spec §29).
  Short version: a real `.magnify` event cannot be synthesised with public APIs,
  ⌘ + scroll is the public substitute, and whether this panel even reports two
  contacts has never been tested.

## Hardware facts

Established by probing a real panel. `docs/v0.1-refactor-plan.md` records the
behaviours the refactor preserves.

- VID `0x2D1F`, PID `0x524C`, product string `Pen and multitouch sensor`.
- **The M14t matches the driver's device filter twice** — two interfaces, both
  `usage 0x04`, with 136 and 25 elements. Their descriptors disagree
  (`0…12372 / 0…6960` versus `0…30931 / 0…17399`) and the panel actually reports
  the first. Calibration is resolved per connected device, so the second
  silently wins. Pre-existing bug, deliberately not fixed in v0.1; scheduled
  with device identification by VID/PID (spec §18).
- There is **no separate Pen collection**. Pen usages — `TipPressure` (0…4095),
  `Eraser`, `Invert`, `XTilt`/`YTilt`, `BarrelSwitch` — live inside the
  136-element touchscreen descriptor. Pen support (spec §12) needs more usages
  from the same stream, not a second device match.
- Values arrive as `ScanTime`, `Y`, `X`, then `TipSwitch` — contact state comes
  *after* the coordinates, so a press maps to a fresh position.
- Matching on usage page `0x0D` alone also catches the MacBook's own trackpad.

## Hard rules (spec §32)

- No kernel extensions, no System Extensions, no private macOS APIs — with one
  exception the user added to the spec: private CoreGraphics/WindowServer calls
  may be used **only** to hide and show the system cursor, only in an isolated
  component, only behind an on/off setting, and only if the app still works when
  the symbols are missing and always gives the pointer back. Never for HID,
  gestures or event injection.
- No third-party dependencies without a strong reason.
- Deployment target macOS 13+ unless a newer API is a major win.
- SwiftUI for UI; AppKit/CoreGraphics/IOKit where required.
- **No `CGEvent` generation inside gesture recognition.**
- **No UI logic inside HID callbacks.** HID callbacks are not on the main queue;
  publish UI state on `@MainActor` (spec §25).
- No hardcoded display index, no hardcoded raw calibration values.
- No god classes.
- Always preserve the original touch→mouse behaviour as **Mouse Mode** fallback.

## Workflow (spec §33)

- Describe the plan before a large refactor.
- Small, commit-sized steps; one subsystem at a time.
- Run `swift build` and `swift test` after each step.
- Confirm gesture semantics with tests, not assumptions.

## Fork-specific notes

Several identifiers still point at upstream and will need renaming when the fork
diverges — not yet done, do not change them incidentally:

- LaunchAgent label `com.talesfonseca.m14ttouch` (`install.sh`, `README.md`)
- Clone URL in `README.md` quick start
