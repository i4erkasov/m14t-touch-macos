import CoreGraphics
import Foundation

/// A snapshot of what the panel is reporting right now, for the diagnostics
/// pane (spec §14).
///
/// Exists because this project has repeatedly had to answer "what is the panel
/// actually sending?" by writing a throwaway probe. A value type so it can
/// cross from the touch queue to the interface without anything shared being
/// mutated on both sides, the same way `DriverStatus` does.
struct LiveInput: Equatable {

    /// Which collection the last value came from.
    var source: InputSource?

    /// The panel's own coordinates, before any mapping or calibration — the
    /// numbers to quote when a touch lands in the wrong place.
    var rawX: Double?
    var rawY: Double?

    /// Where that lands on screen, after calibration and inversion.
    var screen: CGPoint?

    var isTouching = false

    /// How many contacts the panel says it has, when it says.
    ///
    /// Reported as an absence rather than a zero when the usage never arrives:
    /// the descriptor declares `ContactCount`, and whether this panel ever
    /// fills it in is an open question that this view is meant to answer
    /// (`docs/pinch-and-multitouch.md`).
    var contactCount: Int?
    var contactCountMaximum: Int?

    /// Raw pressure as reported, and the same after scaling to 0…1.
    var rawPressure: Double?
    var pressure: Double?

    var penInRange = false
    var penButtons: PenButtons = []

    /// Values arriving per second, over the last second. Says whether the panel
    /// is quiet because nothing is touching it or because nothing is arriving.
    var valuesPerSecond = 0
}
