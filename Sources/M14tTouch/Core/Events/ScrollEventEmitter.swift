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

    func emit(_ action: InputAction) {
        guard case .scroll(let deltaX, let deltaY) = action else { return }

        guard let wheel = accumulator.take(
            x: deltaX * Self.horizontalSign,
            y: deltaY * Self.verticalSign
        ) else { return }

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheel.vertical,
            wheel2: wheel.horizontal,
            wheel3: 0
        ) else {
            FileHandle.standardError.write(
                Data("⚠️  Scroll CGEvent creation failed — is Accessibility permission granted?\n".utf8)
            )
            return
        }

        // Deliberately no `location`. Setting one on a scroll event does not
        // address it anywhere — measured, it warps the cursor. The cursor was
        // already placed on the target when the gesture committed, and moving it
        // again per event is precisely the "arrow chases the finger" behaviour
        // this mode exists to avoid (spec §35).
        event.post(tap: .cghidEventTap)
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
