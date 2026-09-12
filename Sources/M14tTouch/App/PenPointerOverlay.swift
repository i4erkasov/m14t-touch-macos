import AppKit
import QuartzCore
import SwiftUI

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
    private var ringColor: RGBAColor = .systemGreen
    private var style: PenPointerStyle = .arrow
    private var isShowing = false
    private var hasWarmed = false

    init(cursorVisibility: CursorVisibilityController) {
        self.cursorVisibility = cursorVisibility
    }

    /// Follow a change of settings. Main thread.
    func apply(_ configuration: PenConfiguration) {
        let wanted = configuration.pointer.isDrawn
        lock.lock()
        let changed = wanted != isEnabled
        isEnabled = wanted
        lock.unlock()

        diameter = CGFloat(configuration.pointerSize)
        ringColor = configuration.pointerColor
        style = configuration.pointer

        // Built now rather than on the first pen sample. Measured: constructing
        // this window costs 28 ms and showing it for the first time another 3,
        // all on the main thread — which the first stroke after a launch was
        // paying, and which is what made the pen stutter until it had.
        if wanted {
            _ = window ?? makeWindow()
            warmUp()
        }
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

        // Hidden by transparency, not by ordering out. Ordering a window in and
        // out repeatedly is the part that stopped working after the first
        // visit — the pen kept reporting, measured, and the dot stopped
        // appearing — and it is also the slower of the two: 0.19 ms against
        // nothing measurable. A window at alpha zero is invisible and, being
        // click-through already, is in nobody's way.
        if !window.isVisible { window.orderFrontRegardless() }
        if window.alphaValue != 1 { window.alphaValue = 1 }

        // Transitions only, so this stays quiet during a stroke while still
        // being there when the dot does not show up. An overlay that fails to
        // appear has no error to catch — there is simply nothing on screen.
        if !isShowing {
            isShowing = true
            let screen = NSScreen.screens.first { $0.frame.intersects(frame) }
            Log.line("""
                ✒️  Pen dot shown at (\(Int(frame.midX)), \(Int(frame.midY))) \
                on \(screen?.localizedName ?? "no screen"), \
                size \(Int(diameter)), onscreen=\(window.isVisible), \
                alpha=\(window.alphaValue)
                """)
        }
    }

    private func conceal() {
        window?.alphaValue = 0
        if isShowing {
            isShowing = false
            Log.line("✒️  Pen dot hidden")
        }
    }

    /// Pay the cost of the first appearance now, invisibly.
    ///
    /// The compositor allocates a window's surface when it is first shown, and
    /// that is a one-off: measured at 3 ms the first time and 0.1 ms every time
    /// after. Doing it at alpha zero means nothing appears on screen.
    private func warmUp() {
        guard !hasWarmed, let window else { return }
        hasWarmed = true
        window.alphaValue = 0
        window.orderFrontRegardless()
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
    /// The core is a fixed dark rather than a semantic colour. A dynamic colour
    /// resolves against this application's appearance, and this application is
    /// not the one underneath — the dot floats over whatever the pen is pointing
    /// at, so it carries its own contrast: a dark core for pale windows, a
    /// bright ring for dark ones. Only the ring is the user's to choose, which
    /// is why the core is not.
    private func styleDot() {
        guard let layer = window?.contentView?.layer else { return }
        let side = diameter + Self.margin

        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        switch style {
        case .dot, .arrow: layer.addSublayer(makeDot())
        case .crosshair:   makeCrosshair().forEach(layer.addSublayer)
        }

        if let window, window.frame.width != side {
            window.setContentSize(CGSize(width: side, height: side))
        }
    }

    /// A filled disc inside a coloured ring.
    ///
    /// The core is a fixed dark rather than a semantic colour. A dynamic colour
    /// resolves against this application's appearance, and this application is
    /// not the one underneath — the pointer floats over whatever the pen is
    /// pointing at, so it carries its own contrast: a dark core for pale
    /// windows, a bright ring for dark ones. Only the ring is the user's to
    /// choose, which is why the core is not.
    private func makeDot() -> CALayer {
        let inset = Self.margin / 2
        let dot = CALayer()
        dot.frame = CGRect(x: inset, y: inset, width: diameter, height: diameter)
        dot.cornerRadius = diameter / 2
        dot.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        dot.borderColor = ringColor.cgColor
        // A tenth of the diameter is a hairline at any size worth using; a
        // sixth is thick enough that the colour is what the pointer looks like.
        dot.borderWidth = max(1.5, diameter / 6)
        return dot
    }

    /// Four arms around an empty centre.
    ///
    /// Each arm is drawn twice — a dark bar and a coloured one a little thinner
    /// on top — for the same reason the dot has a dark core and a bright ring:
    /// one colour cannot be seen against every window, and this floats over
    /// windows whose colour is not ours to know.
    private func makeCrosshair() -> [CALayer] {
        let centre = (diameter + Self.margin) / 2
        let thickness = max(1.5, diameter / 7)
        let outline = thickness + 2
        let gap = diameter * 0.18
        let arm = diameter / 2 - gap

        // Horizontal pair, then vertical: left, right, down, up.
        let arms: [CGRect] = [
            CGRect(x: centre - gap - arm, y: centre - thickness / 2, width: arm, height: thickness),
            CGRect(x: centre + gap, y: centre - thickness / 2, width: arm, height: thickness),
            CGRect(x: centre - thickness / 2, y: centre - gap - arm, width: thickness, height: arm),
            CGRect(x: centre - thickness / 2, y: centre + gap, width: thickness, height: arm)
        ]

        return arms.flatMap { rect -> [CALayer] in
            let shadow = CALayer()
            shadow.frame = rect.insetBy(dx: -(outline - thickness) / 2, dy: -(outline - thickness) / 2)
            shadow.cornerRadius = min(shadow.frame.width, shadow.frame.height) / 2
            shadow.backgroundColor = NSColor(white: 0.1, alpha: 0.8).cgColor

            let bar = CALayer()
            bar.frame = rect
            bar.cornerRadius = min(rect.width, rect.height) / 2
            bar.backgroundColor = ringColor.cgColor
            return [shadow, bar]
        }
    }

    // MARK: - Geometry

    /// Quartz measures y downwards from the top of the primary display; AppKit
    /// measures it upwards from the bottom of the same one.
    private static func cocoaY(fromQuartz y: CGFloat) -> CGFloat {
        (NSScreen.screens.first?.frame.maxY ?? 0) - y
    }
}

extension RGBAColor {

    /// For drawing. sRGB explicitly, because that is the space the components
    /// were stored in.
    var cgColor: CGColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha).cgColor
    }

    /// For the colour well in the settings window.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Back from the colour well. Falls back to what it was rather than to
    /// nothing, because a colour that cannot be expressed in sRGB — from the
    /// system picker's other models — must not silently become black.
    init(_ color: Color, fallback: RGBAColor) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            self = fallback
            return
        }
        self.init(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent)
        )
    }
}
