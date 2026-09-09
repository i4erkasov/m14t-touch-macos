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
```

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

**Hardware is usually absent.** Never assume the M14t is plugged in. All core
logic must be testable without it (spec §32) — that is the main reason
`CoordinateMapper` is a pure value type. Behaviour that genuinely requires the
panel must be reported as unverified, not assumed to work.

**Do not guess HID usages.** If a usage is unknown, add diagnostics to capture it
from a real device first (spec §33.7, §18).

## Current architecture (pre-refactor)

```
IOHIDManager ──▶ HIDTouchDriver ──▶ CoordinateMapper ──▶ MouseEmitter ──▶ CGEvent
                (orchestration +
                 touch state machine)
```

| File | Responsibility |
|---|---|
| `main.swift` | Entry point: dispatch, permission check, run loop |
| `ArgumentParser.swift` | Pure CLI parsing → `TouchConfig` |
| `TouchConfig.swift` | Runtime options value type |
| `HIDTouchDriver.swift` | IOKit orchestration + contact state + auto-calibration |
| `CoordinateMapper.swift` | **Pure** raw→screen math (unit tested) |
| `Calibration.swift` | `CalibrationData` + JSON store at `~/.m14ttouch.json` |
| `DisplayResolver.swift` | `CGGetActiveDisplayList` wrapper |
| `MouseEmitter.swift` | `CGEvent` posting |
| `HIDUsage.swift` | Named HID usage constants |

`HIDTouchDriver` currently does too much: it both reads HID *and* decides that
movement means drag. Splitting that is the point of v0.1 (spec §34).

Calibration precedence: manual CLI flags > saved `~/.m14ttouch.json` > HID descriptor.

## Target architecture (spec §4)

```
HID input ──▶ TouchFrame/TouchPoint ──▶ GestureRecognizer ──▶ InputAction ──▶ EventEmitter
```

Keep these layers separate: HID acquisition · mapping · calibration · gesture
recognition · event emission · UI · persistence.

## Hard rules (spec §32)

- No kernel extensions, no System Extensions, no private macOS APIs.
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
