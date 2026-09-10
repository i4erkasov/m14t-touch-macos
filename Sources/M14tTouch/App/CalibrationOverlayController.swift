import AppKit
import SwiftUI

/// Puts the calibration overlay on the panel and feeds it touches (spec §15).
@MainActor
final class CalibrationOverlayController: ObservableObject {

    @Published private(set) var session = GuidedCalibration()

    private let driver: HIDTouchDriver
    private var window: NSWindow?
    private var onFinish: ((CalibrationResult?) -> Void)?

    init(driver: HIDTouchDriver) {
        self.driver = driver
    }

    var isRunning: Bool { window != nil }

    /// Show the overlay on a display.
    ///
    /// - Returns: `false` when the display cannot be found among the screens
    ///   AppKit knows about. Showing the overlay somewhere else would be a dead
    ///   end — the user could not see what to touch, and touching would do
    ///   nothing they could observe.
    @discardableResult
    func begin(on display: DisplayInfo, onFinish: @escaping (CalibrationResult?) -> Void) -> Bool {
        guard !isRunning, let screen = Self.screen(for: display.id) else { return false }

        self.onFinish = onFinish
        session = GuidedCalibration()

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: overlay())
        // The frame is set from the screen rather than from CGDisplayBounds:
        // CoreGraphics measures downwards from the top-left of the desktop and
        // AppKit upwards from the bottom-left, and taking the screen's own frame
        // avoids the conversion and the chance of getting it inverted.
        window.setFrame(screen.frame, display: true)
        self.window = window

        // Touches must reach the overlay and not the pointer, or a finger on a
        // target would press whatever is under it.
        driver.setFrameObserver { [weak self] frame in
            MainActor.assumeIsolated { self?.handle(frame) }
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    // MARK: - Driving

    private func handle(_ frame: TouchFrame) {
        guard isRunning else { return }
        if let pressed = session.handle(frame) {
            press(pressed)
        }
        refreshOverlay()
        if case .finished(let result) = session.phase { finish(with: result) }
    }

    private func press(_ button: GuidedCalibration.Button) {
        session.press(button)
        refreshOverlay()
        if case .finished(let result) = session.phase { finish(with: result) }
    }

    private func overlay() -> CalibrationOverlayView {
        CalibrationOverlayView(
            session: session,
            onPress: { [weak self] button in self?.press(button) },
            onCancel: { [weak self] in self?.finish(with: nil) }
        )
    }

    /// The session is a value, so the hosted view is handed a fresh copy rather
    /// than observing one. Simpler than making it a reference type for the sake
    /// of a screen that exists for half a minute.
    private func refreshOverlay() {
        (window?.contentView as? NSHostingView<CalibrationOverlayView>)?.rootView = overlay()
    }

    private func finish(with result: CalibrationResult?) {
        guard isRunning else { return }
        driver.setFrameObserver(nil)
        window?.orderOut(nil)
        window = nil
        let completion = onFinish
        onFinish = nil
        completion?(result)
    }

    /// The `NSScreen` showing a given CoreGraphics display.
    ///
    /// The two APIs describe the same displays and share no type; the screen
    /// number in `deviceDescription` is the bridge.
    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == id
        }
    }
}
