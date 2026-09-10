import AppKit
import QuartzCore

/// Draws a dot where the pen is, in place of the system arrow.
///
/// Entirely public API. macOS gives no way for one application to replace
/// another's cursor image — `NSCursor` applies only over the setting
/// application's own windows while it is frontmost, and a touch driver is never
/// the frontmost app — so the dot is a small window that follows the pen, and
/// the arrow underneath is hidden by the same facility the finger modes use.
///
/// It is a *small* window rather than one transparent sheet over the desktop,
/// which is what this started as. With "Displays have separate Spaces" — on by
/// default — a window belongs to one display's space, so a sheet spanning three
/// displays was shown on one of them and the dot, positioned over the panel,
/// landed outside it. The window server reported it visible the whole time.
///
/// Two threads meet here. `moved(to:)` and `left()` arrive on the touch queue
/// at whatever rate the panel reports; everything that touches AppKit happens
/// on the main thread, and the two are joined by a coalescing hop so a burst of
/// samples becomes one move rather than a queue of them.
final class PenPointerOverlay: PenPointerDisplay {

    /// Room around the dot for its outline, so the border is not clipped by the
    /// window edge.
    private static let margin: CGFloat = 4

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
        styleDot()

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

        let side = diameter + Self.margin
        let frame = CGRect(
            x: point.x - side / 2,
            y: Self.cocoaY(fromQuartz: point.y) - side / 2,
            width: side,
            height: side
        )
        window.setFrame(frame, display: false)
        if !window.isVisible { window.orderFrontRegardless() }

        // Said once per appearance, because an overlay that fails to appear is
        // otherwise silent: there is no error to catch, just nothing on screen.
        if !hasReportedAppearance {
            hasReportedAppearance = true
            let screen = NSScreen.screens.first { $0.frame.intersects(frame) }
            Log.line("""
                ✒️  Pen dot at (\(Int(frame.midX)), \(Int(frame.midY))) \
                on \(screen?.localizedName ?? "no screen"), \
                size \(Int(diameter)), visible=\(window.isVisible)
                """)
        }
    }

    private func conceal() {
        window?.orderOut(nil)
        hasReportedAppearance = false
    }

    private func makeWindow() -> NSPanel {
        let side = diameter + Self.margin
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        // An NSPanel hides itself whenever its application is not active, and a
        // menu-bar accessory is almost never active.
        panel.hidesOnDeactivate = false
        // The whole point is to be looked through: the dot must never take a
        // click away from the application the pen is actually using.
        panel.ignoresMouseEvents = true
        // Above menus, because the pen is used over them too.
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle
        ]

        let host = NSView()
        host.wantsLayer = true
        panel.contentView = host

        self.window = panel
        styleDot()
        return panel
    }

    /// The window *is* the dot: one layer, sized and rounded to match.
    ///
    /// Fixed colours rather than the semantic ones. A dynamic colour resolves
    /// against this application's appearance, and this application is not the
    /// one underneath — the dot floats over whatever the pen is pointing at, so
    /// it carries its own contrast: a dark core inside a light ring reads on
    /// both.
    private func styleDot() {
        guard let layer = window?.contentView?.layer else { return }
        let side = diameter + Self.margin
        let inset = Self.margin / 2

        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let dot = CALayer()
        dot.frame = CGRect(x: inset, y: inset, width: diameter, height: diameter)
        dot.cornerRadius = diameter / 2
        dot.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        dot.borderColor = NSColor(white: 1.0, alpha: 0.95).cgColor
        dot.borderWidth = max(1, diameter / 10)
        layer.addSublayer(dot)

        if let window, window.frame.width != side {
            window.setContentSize(CGSize(width: side, height: side))
        }
    }

    // MARK: - Geometry

    /// Quartz measures y downwards from the top of the primary display; AppKit
    /// measures it upwards from the bottom of the same one.
    private static func cocoaY(fromQuartz y: CGFloat) -> CGFloat {
        (NSScreen.screens.first?.frame.maxY ?? 0) - y
    }
}
