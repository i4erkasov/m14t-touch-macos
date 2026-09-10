import AppKit
import SwiftUI

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
@MainActor
final class AppController: NSObject, NSApplicationDelegate {

    private let driver: HIDTouchDriver
    private let cursorVisibility: CursorVisibilityController
    private let settingsStore: SettingsStore

    private var settings: AppSettings
    private var status = DriverStatus()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?
    private lazy var calibrationOverlay = CalibrationOverlayController(driver: driver)

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
            // The driver documents this as main-queue delivery, which is what
            // makes the assumption safe; asserting it here rather than hopping
            // again keeps the status honest about where it already is.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.status = status
                self.settingsModel?.update(status: status)
                self.updateStatusItemAppearance()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationBecameActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

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

    /// The user grants permissions in System Settings and comes back; nothing
    /// notifies us, so returning to the front is the cue to look again.
    @objc private func applicationBecameActive() {
        settingsModel?.refresh()
    }

    @objc private func startCalibration() {
        guard let display = DisplayResolver.resolve(settings.display)?.display else { return }

        let started = calibrationOverlay.begin(on: display) { [weak self] result in
            guard let self, let result else { return }   // cancelled: keep what was there
            CalibrationStore.shared.save(result.calibration, for: display.identity)
            // The solver works out which way the panel counts, so the user does
            // not have to find a checkbox to report that it is mirrored.
            self.settings.invertX = result.invertX
            self.settings.invertY = result.invertY
            self.persist()
            self.driver.apply(self.settings)
            self.settingsModel?.settings = self.settings
            self.settingsModel?.refresh()
        }

        if !started {
            // The chosen display is not among the screens AppKit knows about, so
            // there is nowhere to put the overlay that the user could see.
            let alert = NSAlert()
            alert.messageText = "Can't show the calibration screen"
            alert.informativeText = "The display chosen in Settings isn't connected."
            alert.runModal()
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil { makeSettingsWindow() }
        // A menu-bar app is an accessory: without activating, its window opens
        // behind whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        settingsModel?.refresh()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() {
        let model = SettingsModel(settings: settings, status: status) { [weak self] updated in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The window is the source of truth while it is open, so the
                // menu and the running driver both follow it.
                self.settings = updated
                self.driver.apply(updated)
                self.cursorVisibility.setPolicy(updated.gestures.cursorHiding)
                self.updateStatusItemAppearance()
            }
        }
        model.startCalibration = { [weak self] in
            self?.settingsWindow?.orderOut(nil)   // it would sit over the overlay
            self?.startCalibration()
        }
        settingsModel = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            // Resizable, because a settings window that cannot be resized is one
            // more thing that does not behave like the rest of the system.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "M14t Touch Settings"
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
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
        // Item state is decided here, from current state; without this AppKit
        // re-enables items by its own rules and Calibrate would be clickable
        // with no panel attached.
        menu.autoenablesItems = false
        menu.removeAllItems()

        // The monitor's name, not the touch interface's. "Pen and multitouch
        // sensor" is what the HID descriptor calls itself; nobody owns one of
        // those, they own an M14t.
        menu.addItem(disabled(displayName))
        menu.addItem(connectionItem())
        menu.addItem(.separator())

        let enable = NSMenuItem(
            title: "Touch enabled", action: #selector(toggleEnabled), keyEquivalent: ""
        )
        enable.target = self
        enable.state = settings.enabled ? .on : .off
        menu.addItem(enable)

        // Mode moved to the settings window. A menu is for the handful of things
        // wanted mid-task, and choosing a gesture model is not one of them.
        menu.addItem(.separator())
        let calibrate = NSMenuItem(
            title: "Calibrate…", action: #selector(startCalibration), keyEquivalent: ""
        )
        calibrate.target = self
        calibrate.isEnabled = status.isConnected
        menu.addItem(calibrate)

        // No ⌘, here. That shortcut belongs to an application menu, and in a
        // status menu it only works while the menu is already open — showing a
        // shortcut nobody can use from anywhere else.
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(showSettings), keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))
    }

    /// The connection line, with a green dot when there is something to be
    /// connected to.
    ///
    /// Enabled but without an action rather than disabled: macOS greys a
    /// disabled item whole, colour and all, so the dot would be the same grey as
    /// the word beside it and say nothing. With `autoenablesItems` off, an
    /// enabled item with no action draws normally and still does nothing when
    /// clicked.
    private func connectionItem() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true

        let connected = status.isConnected
        let text = NSMutableAttributedString(string: connected ? "● Connected" : "○ Not connected")
        // Only the dot carries the colour. Colouring the words as well would
        // make a status line shout.
        text.addAttribute(
            .foregroundColor,
            value: connected ? NSColor.systemGreen : NSColor.tertiaryLabelColor,
            range: NSRange(location: 0, length: 1)
        )
        text.addAttribute(
            .foregroundColor,
            value: NSColor.secondaryLabelColor,
            range: NSRange(location: 1, length: text.length - 1)
        )
        item.attributedTitle = text
        return item
    }

    /// What to call the panel in the menu.
    private var displayName: String {
        DisplayResolver.resolve(settings.display)?.display.name ?? "Touch display"
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
