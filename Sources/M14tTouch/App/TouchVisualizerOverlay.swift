import AppKit
import QuartzCore

/// Draws a ring wherever the panel says a finger is.
///
/// Built the way the pen's dot is, and for the same measured reasons: a small
/// window per circle rather than one sheet over the desktop, because a window
/// belongs to one display's space and a sheet spanning several is shown on only
/// one of them; and hidden by transparency rather than by ordering out, because
/// ordering a window in and out repeatedly stopped working after the first
/// cycle (`docs/pinch-and-multitouch.md`, `docs/M14t_PEN_CAPABILITIES.md`).
///
/// A diagnostic, so it is deliberately conspicuous — a wide translucent ring
/// with a bright edge, nothing like the pen's discreet dot.
final class TouchVisualizerOverlay: TouchPointDisplay {

    /// The panel reports five contacts, so five circles is all that can ever be
    /// wanted; built once when switched on rather than during a touch, since a
    /// window costs about 28 ms to create and that would be paid mid-gesture.
    private static let capacity = 5

    /// Roughly a fingertip. Large enough to be found on a 1920-wide panel at
    /// arm's length, which is the point of it.
    private static let diameter: CGFloat = 56

    private let lock = NSLock()
    private var pending: [CGPoint]?
    private var isDrainScheduled = false

    // Main thread only, below here.
    private var circles: [NSPanel] = []

    // MARK: - TouchPointDisplay

    func show(_ points: [CGPoint]) {
        lock.lock()
        pending = points
        let needsHop = !isDrainScheduled
        isDrainScheduled = true
        lock.unlock()

        guard needsHop else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.drain() }
        }
    }

    // MARK: - Main thread

    /// Build the windows now, so the first touch does not pay for them.
    func prepare() {
        while circles.count < Self.capacity { circles.append(makeCircle()) }
    }

    /// Take every circle off the screen.
    func clear() {
        circles.forEach { $0.alphaValue = 0 }
    }

    private func drain() {
        lock.lock()
        let points = pending
        pending = nil
        isDrainScheduled = false
        lock.unlock()

        guard let points else { return }
        prepare()

        for (index, circle) in circles.enumerated() {
            guard index < points.count else {
                circle.alphaValue = 0
                continue
            }
            let point = points[index]
            let side = Self.diameter
            circle.setFrame(
                CGRect(
                    x: point.x - side / 2,
                    y: Self.cocoaY(fromQuartz: point.y) - side / 2,
                    width: side, height: side
                ),
                display: false
            )
            if !circle.isVisible { circle.orderFrontRegardless() }
            circle.alphaValue = 1
        }
    }

    private func makeCircle() -> NSPanel {
        let side = Self.diameter
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
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle
        ]
        panel.alphaValue = 0

        let host = NSView()
        host.wantsLayer = true
        panel.contentView = host

        let ring = CALayer()
        ring.frame = CGRect(x: 3, y: 3, width: side - 6, height: side - 6)
        ring.cornerRadius = (side - 6) / 2
        // Fixed colours: this floats over other applications, whose appearance
        // is not ours to resolve against.
        ring.backgroundColor = NSColor(srgbRed: 0.0, green: 0.55, blue: 1.0, alpha: 0.25).cgColor
        ring.borderColor = NSColor(srgbRed: 0.0, green: 0.55, blue: 1.0, alpha: 0.95).cgColor
        ring.borderWidth = 3
        host.layer?.addSublayer(ring)

        // Shown once at alpha zero, so the compositor allocates its surface now
        // rather than during the first touch.
        panel.orderFrontRegardless()
        return panel
    }

    private static func cocoaY(fromQuartz y: CGFloat) -> CGFloat {
        (NSScreen.screens.first?.frame.maxY ?? 0) - y
    }
}
