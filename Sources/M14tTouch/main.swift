import AppKit
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
        var tags: [String] = []
        if d.isMain { tags.append("main") }
        tags.append(d.isBuiltin ? "built-in" : "external")
        if !d.identity.isUsable { tags.append("no identity — can only be selected by index") }
        print("   [\(d.index)]  \(Int(d.bounds.width)) × \(Int(d.bounds.height))  @ (\(Int(d.bounds.minX)),\(Int(d.bounds.minY)))  — \(tags.joined(separator: ", "))")
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

/// Build the pipeline both the CLI and the app run.
///
/// Returns the controller alongside the engine because shutdown needs it
/// directly: whoever stops the driver also has to give the pointer back.
func makeEngine(for config: TouchConfig)
    -> (engine: TouchEngine, cursorVisibility: CursorVisibilityController) {
    // Always the private implementation, whatever the setting says right now:
    // it resolves nothing until hiding is actually asked for, and choosing at
    // launch from the setting at launch meant enabling hiding later did nothing.
    let cursorVisibility = CursorVisibilityController(
        policy: config.gestures.cursorHiding,
        visibility: PrivateCursorVisibility()
    )
    // The glide outlives the gesture, and the pointer has to stay where the
    // gesture was until it ends — a scroll goes wherever the pointer is. So the
    // scroll emitter says when it has finished and the mouse emitter takes the
    // pointer home then, rather than at the moment the finger lifted.
    let mouse = MouseEventEmitter()
    let scroll = ScrollEventEmitter()
    scroll.onGlideEnded = { [weak mouse] in mouse?.emit(.cursorRestore) }
    // And the arrow stays hidden for as long as the content is still moving.
    // Uncovering it the instant a finger lifts put it on screen at the one
    // moment it is most obviously in the way: nothing is touching the panel to
    // explain why the page is still going.
    scroll.onGlideRunning = { [cursorVisibility] running in
        cursorVisibility.updateGlide(isRunning: running)
    }

    let engine = TouchEngine(
        recognizer: config.mode.makeRecognizer(config: config),
        emitter: RoutingEventEmitter(mouse: mouse, scroll: scroll),
        cursorVisibility: cursorVisibility
    )
    return (engine, cursorVisibility)
}

/// Keeps the application delegate alive; `NSApplication` does not retain it.
var appDelegate: AnyObject?

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
    if CalibrationStore.shared.resetAll() {
        print("🗑️  Calibration reset (\(CalibrationStore.shared.url.path))")
    } else {
        print("ℹ️  No saved calibration to reset.")
    }
    exit(0)

case .error(let message):
    print("❌ \(message)")
    print(ArgumentParser.usageText)
    exit(1)

case .runApp(let config):
    // Permissions are checked by the app itself in step 7, where it can show
    // status and a button rather than exiting with a message nobody sees — a
    // menu-bar app has no terminal to print to.
    let (engine, cursorVisibility) = makeEngine(for: config)
    let appDriver = HIDTouchDriver(config: config, engine: engine)

    // The application needs this as much as the command line does, and for a
    // worse reason. `applicationWillTerminate` covers Quit; it does not run
    // when the process is signalled, and a menu-bar app is signalled often —
    // by `pkill`, by an installer replacing it, by anything that is not the
    // menu. Dying then leaves the HID manager uncancelled while the panel is
    // held exclusively, and that wedges the pen: the finger collection keeps
    // working, the pen collection goes silent, and only replugging the cable
    // brings it back. Observed, repeatedly, and it cost an afternoon to find.
    let shutdownHandler = ShutdownHandler {
        // The pointer first: being left without a cursor is worse than being
        // left with a held button, and this is the last chance to give it back.
        cursorVisibility.restore()
        appDriver.stop()
        exit(0)
    }
    _ = shutdownHandler

    // Top-level code in main.swift runs on the main thread but is not isolated
    // to it, so the assumption has to be stated rather than inferred.
    MainActor.assumeIsolated {
        let controller = AppController(
            driver: appDriver,
            cursorVisibility: cursorVisibility,
            settings: storedSettings
        )
        let app = NSApplication.shared
        app.delegate = controller
        // Held for the process's lifetime: NSApplication does not retain its
        // delegate, and losing it would take the menu with it.
        appDelegate = controller
        app.run()
    }

case .run(let config):
    print(banner)
    printDisplays()

    print("🎛️  Mode: \(config.mode.rawValue)")

    ensureAccessibilityOrExit(prompt: config.promptForAccessibility)

    let (engine, cursorVisibility) = makeEngine(for: config)
    let hiding = config.gestures.cursorHiding
    if hiding.hidesAnything {
        print(cursorVisibility.isActive
              ? "🫥  Cursor hiding: \(hiding.rawValue)"
              : "🫥  Cursor hiding: '\(hiding.rawValue)' requested but unavailable — continuing without it")
    }

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

    // Same reasoning as in the app: an exclusive claim held across a sleep is
    // how the claim goes stale, and the pen then reports nothing while the
    // finger carries on. Held for the lifetime of the process.
    let powerWatcher = PowerWatcher(
        willSleep: {
            cursorVisibility.restore()
            driver.suspend()
        },
        didWake: { driver.resume() }
    )
    _ = powerWatcher

    driver.start()

    // All work happens in IOKit callbacks scheduled on this run loop.
    RunLoop.main.run()
}
