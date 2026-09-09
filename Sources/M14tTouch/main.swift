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

switch ArgumentParser.parse(arguments) {

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

    // Resolve the mode before asking for permission: no point prompting for
    // Accessibility only to bail out on an unavailable mode.
    guard let recognizer = config.mode.makeRecognizer(config: config) else {
        fputs("""
        ❌ '\(config.mode.rawValue)' mode is not implemented yet — it arrives in v0.2.
           Run with --mode mouse.

        """, stderr)
        exit(1)
    }
    print("🎛️  Mode: \(config.mode.rawValue)")

    ensureAccessibilityOrExit(prompt: config.promptForAccessibility)

    let engine = TouchEngine(recognizer: recognizer, emitter: MouseEventEmitter())
    let driver = HIDTouchDriver(config: config, engine: engine)
    driver.start()

    // All work happens in IOKit callbacks scheduled on this run loop.
    RunLoop.main.run()
}
