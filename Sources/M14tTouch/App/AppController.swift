import AppKit

/// The menu-bar application (spec §13).
///
/// AppKit rather than a SwiftUI `App`, for a reason that is structural rather
/// than aesthetic: a target with a `main.swift` cannot also have an `@main`
/// type, and `main.swift` is what lets one binary be both the CLI and the app.
/// Menus and popovers are AppKit anyway; SwiftUI arrives with the settings
/// window in step 6, hosted inside this (spec §32 allows AppKit where SwiftUI
/// is awkward, and a status item is exactly that).
final class AppController: NSObject, NSApplicationDelegate {

    private let driver: HIDTouchDriver
    private let cursorVisibility: CursorVisibilityController
    private var statusItem: NSStatusItem?

    init(driver: HIDTouchDriver, cursorVisibility: CursorVisibilityController) {
        self.driver = driver
        self.cursorVisibility = cursorVisibility
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon and no menu bar of its own. Set in code as well as in the
        // bundle's LSUIElement, so running the bare binary during development
        // behaves like the packaged app rather than bouncing in the Dock.
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "hand.point.up.left", accessibilityDescription: "M14t Touch"
        )
        item.menu = makeMenu()
        statusItem = item

        driver.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The pointer first: being left without a cursor is worse than being
        // left with a held button, and this is the last chance to give it back.
        cursorVisibility.restore()
        driver.stop()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        // Placeholder until step 5 gives it device status, mode and settings.
        let title = NSMenuItem(title: "M14t Touch", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))
        return menu
    }
}
