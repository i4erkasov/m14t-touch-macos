import AppKit
import QuartzCore

/// Draws a dot where the pen is, in place of the system arrow.
///
/// Entirely public API. macOS gives no way for one application to replace
/// another's cursor image — `NSCursor` applies only over the setting
/// application's own windows while it is frontmost, and a touch driver is never
/// the frontmost app — so the dot is a layer in a transparent window that
/// ignores mouse events, and the arrow underneath is hidden by the same
/// facility the finger modes use.
///
/// Two threads meet here. `moved(to:)` and `left()` arrive on the touch queue
/// at whatever rate the panel reports; everything that touches AppKit happens
/// on the main thread, and the two are joined by a coalescing hop so a burst of
/// samples becomes one redraw rather than a queue of them.
final class PenPointerOverlay: PenPointerDisplay {

    /// The latest thing the pen did, waiting to be drawn.
    private enum Update {
        case at(CGPoint)
        case gone
    }

    private let cursorVisibility: CursorVisibilityController

    private let lock = NSLock()
    private var isEnabled = false
    private var pending: Update?
    private var isDrainScheduled = false

    // Main thread only, below here.
    private var window: NSPanel?
    private var dot: CALayer?
    private var diameter: CGFloat = 14
    private var hasReportedAppearance = false

    init(cursorVisibility: CursorVisibilityController) {
        self.cursorVisibility = cursorVisibility
    }

    /// Follow a change of settings. Main thread.
    func apply(_ configuration: PenConfiguration) {
        let wanted = configuration.pointer == .dot
        lock.lock()
        let changed = wanted != isEnabled
        isEnabled = wanted
        lock.unlock()

        diameter = CGFloat(configuration.pointerSize)
        resizeDot()
        if changed {
            Log.line("✒️  Pen pointer: \(configuration.pointer.rawValue)")
        }

        // Switching the dot off has to take it away now. Waiting for the next
        // pen sample would leave it on screen for as long as the pen stays away,
        // and waiting for the arrow would leave the pointer hidden.
        if changed, !wanted { conceal() }
    }

    // MARK: - PenPointerDisplay

    func moved(to point: CGPoint) {
        lock.lock()
        guard isEnabled else { lock.unlock(); return }
        lock.unlock()

        // Asserted here rather than on the main thread: the window server stops
        // honouring a hide the moment the pointer moves, and the pointer is
        // moving on this queue, one sample ahead of the drawing.
        cursorVisibility.updatePenPointer(isDrawn: true)
        schedule(.at(point))
    }

    func left() {
        lock.lock()
        let wasEnabled = isEnabled
        lock.unlock()
        guard wasEnabled else { return }

        cursorVisibility.updatePenPointer(isDrawn: false)
        schedule(.gone)
    }

    // MARK: - Crossing to the main thread

    /// Remember the newest state and ask for one drain, not one per sample.
    private func schedule(_ update: Update) {
        lock.lock()
        pending = update
        let needsHop = !isDrainScheduled
        isDrainScheduled = true
        lock.unlock()

        guard needsHop else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.drain() }
        }
    }

    private func drain() {
        lock.lock()
        let update = pending
        pending = nil
        isDrainScheduled = false
        lock.unlock()

        switch update {
        case .at(let point): reveal(at: point)
        case .gone:          conceal()
        case nil:            break
        }
    }

    // MARK: - The window

    private func reveal(at point: CGPoint) {
        let window = self.window ?? makeWindow()
        guard let dot else { return }

        // The overlay spans every screen, so it has to be re-laid-out when the
        // screens change — a display arriving or leaving moves the origin the
        // dot's position is measured from.
        let frame = Self.desktopFrame()
        if window.frame != frame { window.setFrame(frame, display: false) }

        // Implicit animation off: a pointer that eases towards where the pen
        // already is would be a pointer that is always wrong.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.position = CGPoint(
            x: point.x - frame.minX,
            y: Self.cocoaY(fromQuartz: point.y) - frame.minY
        )
        CATransaction.commit()

        if !window.isVisible { window.orderFrontRegardless() }

        // Said once per appearance, because an overlay that fails to appear is
        // otherwise silent: there is no error to catch, just nothing on screen.
        if !hasReportedAppearance {
            hasReportedAppearance = true
            Log.line("""
                ✒️  Pen dot shown at (\(Int(dot.position.x)), \(Int(dot.position.y))) \
                in window \(Int(frame.width))×\(Int(frame.height)) @ \
                (\(Int(frame.minX)),\(Int(frame.minY))), visible=\(window.isVisible), \
                size=\(Int(diameter))
                """)
        }
    }

    private func conceal() {
        window?.orderOut(nil)
        hasReportedAppearance = false
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: Self.desktopFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        // An NSPanel hides itself whenever its application is not active, and a
        // menu-bar accessory is almost never active — the dot would have been
        // ordered in and taken straight back out again, every time.
        panel.hidesOnDeactivate = false
        // The whole point is to be looked through: the dot must never take a
        // click away from the application the pen is actually using.
        panel.ignoresMouseEvents = true
        // Above menus, because the pen is used over them too.
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle
        ]

        let host = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        host.wantsLayer = true
        panel.contentView = host

        let dot = CALayer()
        dot.backgroundColor = NSColor.labelColor.withAlphaComponent(0.85).cgColor
        // An outline in the opposite colour, so the dot is visible on a dark
        // window and a light one without knowing which it is over.
        dot.borderColor = NSColor.textBackgroundColor.withAlphaComponent(0.9).cgColor
        dot.borderWidth = 1.5
        host.layer?.addSublayer(dot)

        self.window = panel
        self.dot = dot
        resizeDot()
        return panel
    }

    private func resizeDot() {
        guard let dot else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        dot.cornerRadius = diameter / 2
        CATransaction.commit()
    }

    // MARK: - Geometry

    /// Every screen as one rectangle, in AppKit coordinates.
    private static func desktopFrame() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// Quartz measures y downwards from the top of the primary display; AppKit
    /// measures it upwards from the bottom of the same one.
    private static func cocoaY(fromQuartz y: CGFloat) -> CGFloat {
        (NSScreen.screens.first?.frame.maxY ?? 0) - y
    }
}
