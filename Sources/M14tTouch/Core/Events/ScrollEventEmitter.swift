import CoreGraphics
import Foundation

/// Turns scroll actions into pixel-unit scroll wheel events (spec §23).
final class ScrollEventEmitter: EventEmitter {

    /// How a finger delta maps onto the wheel axes.
    ///
    /// Established on the panel rather than taken from documentation, as spec
    /// §23 requires: a positive `wheel1` moved the content toward the beginning
    /// of the document, which is exactly where a finger travelling *down* should
    /// take it under natural scrolling. So the vertical delta maps straight
    /// through, unflipped.
    ///
    /// The horizontal axis was not measured — only vertical scrolling was tested
    /// on the device — and assumes the same convention. If sideways scrolling
    /// ever comes out backwards, this is the line to change.
    private static let verticalSign: Double = 1
    private static let horizontalSign: Double = 1

    private var accumulator = ScrollAccumulator()
    private var phases = ScrollPhaseTracker()

    /// Where the glide after a flick is produced.
    ///
    /// A timer, because a glide is a thing that happens over time and no frame
    /// arrives to drive it — the finger has gone. Its own queue, so it neither
    /// waits on the touch pipeline nor holds it up.
    private let glideQueue = DispatchQueue(label: "com.m14ttouch.momentum")
    private var glide: DispatchSourceTimer?

    /// Called when a glide finishes of its own accord, so the pointer can go
    /// home. Set by whoever assembles the emitters, because putting the pointer
    /// back is the mouse emitter's business and not this one's.
    var onGlideEnded: (() -> Void)?

    func emit(_ action: InputAction) {
        if case .scrollMomentum(let velocity, let restoresCursor) = action {
            startGlide(from: velocity, restoringCursor: restoresCursor)
            return
        }

        // Any new movement of a finger ends the old glide. Touching the screen
        // to stop a moving page is the gesture everyone already knows.
        stopGlide()

        if case .scrollEnd = action {
            guard let phase = phases.end() else { return }
            // The remainder belongs to the gesture that just finished. Carrying
            // it into the next one would start that one with a jump.
            accumulator = ScrollAccumulator()
            post(vertical: 0, horizontal: 0, phase: phase)
            return
        }

        guard case .scroll(let deltaX, let deltaY) = action else { return }

        guard let wheel = accumulator.take(
            x: deltaX * Self.horizontalSign,
            y: deltaY * Self.verticalSign
        ) else { return }

        post(vertical: wheel.vertical, horizontal: wheel.horizontal, phase: phases.delta())
    }

    /// Keep scrolling after the finger has gone, slowing to a stop.
    private func startGlide(from velocity: CGVector, restoringCursor: Bool) {
        stopGlide()

        var momentum = ScrollMomentum(velocity: velocity)
        var phase = CGMomentumScrollPhase.begin
        var carried = ScrollAccumulator()

        let timer = DispatchSource.makeTimerSource(queue: glideQueue)
        timer.schedule(deadline: .now() + momentum.interval, repeating: momentum.interval)
        timer.setEventHandler { [self] in
            guard let step = momentum.next() else {
                // One last event to say it has stopped, or applications go on
                // believing a glide is in progress.
                post(vertical: 0, horizontal: 0, phase: nil, momentum: .end)
                stopGlide()
                // Only now: the pointer had to stay where the gesture was for
                // as long as the glide was still scrolling there.
                if restoringCursor { onGlideEnded?() }
                return
            }
            guard let wheel = carried.take(x: Double(step.dx), y: Double(step.dy)) else { return }
            post(vertical: wheel.vertical, horizontal: wheel.horizontal,
                 phase: .none, momentum: phase)
            phase = .continuous
        }
        timer.resume()
        glide = timer
    }

    private func stopGlide() {
        glide?.cancel()
        glide = nil
    }

    /// One scroll event, carrying the phase that makes macOS treat it as a
    /// gesture rather than a wheel.    /// One scroll event, carrying the phase that makes macOS treat it as a
    /// gesture rather than a wheel.
    ///
    /// Without a phase — the default is `none` — pixel deltas are a mouse wheel:
    /// no rubber-banding at the end of a document, and no smooth continuous
    /// scrolling in the applications that distinguish the two. A trackpad sends
    /// `began`, then `changed`, then `ended`, and that is what this says.
    /// - Parameter phase: nil while a glide is running. `CGScrollPhase` has no
    ///   case for "none", and the two phases are mutually exclusive: an event
    ///   is part of a gesture or part of its momentum, never both.
    private func post(
        vertical: Int32,
        horizontal: Int32,
        phase: CGScrollPhase?,
        momentum: CGMomentumScrollPhase = .none
    ) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) else {
            FileHandle.standardError.write(
                Data("⚠️  Scroll CGEvent creation failed — is Accessibility permission granted?\n".utf8)
            )
            return
        }

        event.setIntegerValueField(
            .scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0)
        )
        event.setIntegerValueField(
            .scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue)
        )
        // `isContinuous` is already 1 for pixel units — checked rather than set,
        // so nothing here claims to do something the constructor has done.

        // Deliberately no `location`. Setting one on a scroll event does not
        // address it anywhere — measured, it warps the cursor. The cursor was
        // already placed on the target when the gesture committed, and moving it
        // again per event is precisely the "arrow chases the finger" behaviour
        // this mode exists to avoid (spec §35).
        event.post(tap: .cghidEventTap)
    }
}

/// Which phase each posted scroll event should carry.
///
/// Separate from the emitter because the emitter cannot be tested — its output
/// goes into the window server — and this is the part with a decision in it: the
/// first event of a gesture is `began`, the rest are `changed`, and `ended` is
/// sent once and only if a gesture was actually under way.
///
/// "First event" means the first one *posted*, not the first delta seen. A slow
/// drag produces sub-pixel deltas that the accumulator swallows, and a gesture
/// whose `began` was swallowed would never begin at all.
struct ScrollPhaseTracker {

    private var isMidGesture = false

    /// The phase for an event that is about to be posted.
    mutating func delta() -> CGScrollPhase {
        defer { isMidGesture = true }
        return isMidGesture ? .changed : .began
    }

    /// The phase that closes the gesture, or nil when none was open — a finger
    /// that lifted without ever moving a whole pixel.
    mutating func end() -> CGScrollPhase? {
        guard isMidGesture else { return nil }
        isMidGesture = false
        return .ended
    }
}

/// Turns fractional pixel deltas into whole wheel steps without losing the
/// remainder.
///
/// A slow drag produces sub-pixel deltas, especially at low sensitivity.
/// Rounding each one independently would discard them all and the page would
/// not move at all; carrying the remainder means a slow scroll still arrives,
/// just later.
struct ScrollAccumulator {

    /// Guards against a wild sensitivity overflowing the event's Int32 fields.
    private static let limit: Double = 10_000

    private var pendingX: Double = 0
    private var pendingY: Double = 0

    /// - Returns: whole wheel steps, or `nil` when what has accumulated so far
    ///   does not yet amount to a whole pixel on either axis.
    mutating func take(x: Double, y: Double) -> (horizontal: Int32, vertical: Int32)? {
        pendingX = (pendingX + x).clamped(to: Self.limit)
        pendingY = (pendingY + y).clamped(to: Self.limit)

        let horizontal = pendingX.rounded(.towardZero)
        let vertical = pendingY.rounded(.towardZero)
        guard horizontal != 0 || vertical != 0 else { return nil }

        pendingX -= horizontal
        pendingY -= vertical
        return (Int32(horizontal), Int32(vertical))
    }
}

private extension Double {
    func clamped(to limit: Double) -> Double {
        Swift.min(Swift.max(self, -limit), limit)
    }
}
