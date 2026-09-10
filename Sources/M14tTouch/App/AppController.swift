import AppKit

/// The menu-bar application (spec §13).
///
/// AppKit rather than a SwiftUI `App`, for a reason that is structural rather
/// than aesthetic: a target with a `main.swift` cannot also have an `@main`
/// type, and `main.swift` is what lets one binary be both the CLI and the app.
/// SwiftUI arrives with the settings window in step 6, hosted inside this.
///
/// Everything here runs on the main thread. The driver runs on its own queue and
/// the two meet in exactly two places: `onStatusChange`, which it delivers on
/// main, and the `setEnabled`/`setMode` commands, which hop onto its queue.
final class AppController: NSObject, NSApplicationDelegate {

    private let driver: HIDTouchDriver
    private let cursorVisibility: CursorVisibilityController
    private let settingsStore: SettingsStore

    private var settings: AppSettings
    private var status = DriverStatus()
    private var statusItem: NSStatusItem?

    init(
        driver: HIDTouchDriver,
        cursorVisibility: CursorVisibilityController,
        settings: AppSettings,
        settingsStore: SettingsStore = .shared
    ) {
        self.driver = driver
        self.cursorVisibility = cursorVisibility
        self.settings = settings
        self.settingsStore = settingsStore
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon and no menu bar of its own. Set in code as well as in the
        // bundle's LSUIElement, so running the bare binary during development
        // behaves like the packaged app rather than bouncing in the Dock.
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "hand.point.up.left", accessibilityDescription: "M14t Touch"
        )
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        driver.onStatusChange = { [weak self] status in
            self?.status = status
            self?.updateStatusItemAppearance()
        }

        driver.setEnabled(settings.enabled)
        driver.start()
        updateStatusItemAppearance()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The pointer first: being left without a cursor is worse than being
        // left with a held button, and this is the last chance to give it back.
        cursorVisibility.restore()
        driver.stop()
    }

    /// Dim the icon when touch is off or the panel is away, so the menu bar says
    /// at a glance whether anything is happening.
    private func updateStatusItemAppearance() {
        let live = settings.enabled && status.isConnected
        statusItem?.button?.appearsDisabled = !live
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        driver.setEnabled(settings.enabled)
        persist()
        updateStatusItemAppearance()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = TouchMode(rawValue: sender.representedObject as? String ?? "") else { return }
        settings.mode = mode
        driver.setMode(mode)
        persist()
    }

    private func persist() {
        settingsStore.save(settings)
    }
}

// MARK: - Menu

extension AppController: NSMenuDelegate {

    /// Rebuilt each time it opens rather than mutated in place, so what it shows
    /// is derived from the current state and cannot drift out of step with it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled(status.isConnected
            ? "● \(status.deviceName ?? "Touch device") connected"
            : "○ No touch device"))
        menu.addItem(.separator())

        let enable = NSMenuItem(
            title: "Enable touch", action: #selector(toggleEnabled), keyEquivalent: ""
        )
        enable.target = self
        enable.state = settings.enabled ? .on : .off
        menu.addItem(enable)

        menu.addItem(.separator())
        menu.addItem(disabled("Mode"))
        for mode in TouchMode.allCases {
            let item = NSMenuItem(title: title(for: mode), action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.mode == mode ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))
    }

    private func title(for mode: TouchMode) -> String {
        switch mode {
        case .touchscreen: return "Touchscreen"
        case .mouse:       return "Mouse"
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
