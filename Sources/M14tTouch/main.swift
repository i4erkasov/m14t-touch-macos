import Foundation
import CoreGraphics
import ApplicationServices

// ─────────────────────────────────────────────
//  m14ttouch — entry point
//
//  Parses arguments, handles one-shot actions (list / reset / help), verifies
//  permissions, then starts the driver on the main run loop.
// ─────────────────────────────────────────────

let banner = """

  ┌─────────────────────────────────────────┐
  │  m14ttouch · M14t touch driver for macOS │
  └─────────────────────────────────────────┘
"""

/// Print the list of connected displays.
func printDisplays() {
    print("📺 Connected displays:")
    for d in DisplayResolver.all() {
        let tag = d.isMain ? "  ← main" : ""
        print("   [\(d.index)]  \(Int(d.bounds.width)) × \(Int(d.bounds.height))  @ (\(Int(d.bounds.minX)),\(Int(d.bounds.minY)))\(tag)")
    }
}

/// Ensure Accessibility permission (needed to post mouse events). Exits if absent
/// so the user can grant it and relaunch cleanly.
func ensureAccessibilityOrExit(prompt: Bool) {
    guard !AXIsProcessTrusted() else { return }

    let message = """
    ⚠️  Accessibility permission is required to move the cursor.

        System Settings → Privacy & Security → Accessibility
        → enable the terminal app (or the m14ttouch binary), then relaunch.

    """
    fputs(message, stderr)

    if prompt {
        // Trigger the system prompt, then exit.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        exit(1)
    }

    exit(1)
}

// MARK: - Dispatch

let arguments = Array(CommandLine.arguments.dropFirst())

// Stored preferences first, command-line flags over the top. Nothing writes
// these yet — the settings window does, in v0.3 step 6 — so today this is the
// defaults unless the value was put there by hand.
let storedSettings = SettingsStore.shared.loadOrDefault()

switch ArgumentParser.parse(arguments, defaults: storedSettings.touchConfig) {

case .help:
    print(ArgumentParser.usageText)
    exit(0)

case .listDisplays:
    printDisplays()
    exit(0)

case .resetCalibration:
    if CalibrationStore.shared.reset() {
        print("🗑️  Calibration reset (\(CalibrationStore.shared.url.path))")
    } else {
        print("ℹ️  No saved calibration to reset.")
    }
    exit(0)

case .error(let message):
    print("❌ \(message)")
    print(ArgumentParser.usageText)
    exit(1)

case .run(let config):
    print(banner)
    printDisplays()

    print("🎛️  Mode: \(config.mode.rawValue)")

    ensureAccessibilityOrExit(prompt: config.promptForAccessibility)

    let hiding = config.gestures.cursorHiding
    let cursorVisibility = CursorVisibilityController(
        policy: hiding,
        visibility: hiding.hidesAnything ? PrivateCursorVisibility() : PublicCursorVisibility()
    )
    if hiding.hidesAnything {
        print(cursorVisibility.isActive
              ? "🫥  Cursor hiding: \(hiding.rawValue)"
              : "🫥  Cursor hiding: '\(hiding.rawValue)' requested but unavailable — continuing without it")
    }

    let engine = TouchEngine(
        recognizer: config.mode.makeRecognizer(config: config),
        emitter: RoutingEventEmitter(
            mouse: MouseEventEmitter(),
            scroll: ScrollEventEmitter()
        ),
        cursorVisibility: cursorVisibility
    )
    let driver = HIDTouchDriver(config: config, engine: engine)

    // Held for the lifetime of the process: the signal sources stop firing when
    // they are deallocated.
    let shutdownHandler = ShutdownHandler {
        print("\n👋 Stopping — releasing any held contact and the pointer.")
        // The pointer first: a hidden cursor is worse to be left with than a
        // held button, and this is the only chance to give it back.
        cursorVisibility.restore()
        driver.stop()
        exit(0)
    }
    _ = shutdownHandler

    driver.start()

    // All work happens in IOKit callbacks scheduled on this run loop.
    RunLoop.main.run()
}
