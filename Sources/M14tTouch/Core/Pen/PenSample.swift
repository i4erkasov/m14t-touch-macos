import CoreGraphics
import Foundation

/// Which end of the stylus is touching.
///
/// Not a guess at what a button might mean: the device reports `Eraser` in place
/// of `TipSwitch` when the near button is held, and the two never overlap
/// (`M14t_PEN_CAPABILITIES.md`).
enum PenTool: Equatable {
    case tip
    case eraser
}

/// Buttons the stylus reports.
///
/// An option set rather than named fields, as the pen spec §8 asks, so a second
/// device with different buttons does not need the type changed.
struct PenButtons: OptionSet, Equatable {
    let rawValue: UInt32

    /// The button furthest from the tip, reported as `BarrelSwitch`. The one
    /// free to be mapped to something.
    static let barrel = PenButtons(rawValue: 1 << 0)

    /// The button nearest the tip, reported as `Invert`: holding it puts the pen
    /// in eraser orientation rather than pressing anything. Recorded because the
    /// state is visible in hover, before any contact makes it an eraser stroke.
    static let eraserMode = PenButtons(rawValue: 1 << 1)
}

/// One reading of the pen (pen spec §8).
///
/// Tilt, rotation and azimuth are absent on purpose. The descriptor declares
/// tilt over −90…90 and the device never sends it — checked with the pen
/// demonstrably working — so fields for them would be permanently nil, which is
/// the data-model version of a dead setting.
struct PenSample: Equatable {

    let timestamp: TimeInterval

    /// Raw panel coordinate, in the pen's own space — which is *not* the
    /// finger's: 0…30931 × 0…17399 against 0…12372 × 0…6960.
    let rawPosition: CGPoint

    /// Position on the target display, in the global screen coordinate space.
    let position: CGPoint

    /// The pen is close enough to be tracked, whether or not it is touching.
    let inProximity: Bool

    /// Which end is touching, if either.
    let contact: PenTool?

    /// Contact force, normalised to 0…1, or `nil` when nothing is touching.
    let pressure: Double?

    let buttons: PenButtons

    /// Stylus battery, 0…1, when reported.
    let battery: Double?
}

/// Turns raw pressure into 0…1.
///
/// The naive normalisation — over the descriptor's whole 0…4095 — is wrong on
/// this hardware, and measurably so. The lightest touch that registers at all
/// peaks around 1370, because anything lighter never sets the contact switch. So
/// the bottom third of the declared range cannot occur, and normalising over it
/// would start every possible stroke at a third of full strength and leave the
/// lower half of any pressure curve dead.
struct PressureScale: Equatable {

    /// The lightest raw value a real contact produces.
    let floor: Double

    /// The heaviest, from the descriptor and confirmed reachable.
    let ceiling: Double

    /// Measured on the M14t: lightest contacts peaked at 1367 and 1382, and a
    /// firm press reached 4095 exactly.
    static let m14t = PressureScale(floor: 1350, ceiling: 4095)

    func normalize(_ raw: Double) -> Double {
        guard ceiling > floor else { return 0 }
        return min(max((raw - floor) / (ceiling - floor), 0), 1)
    }

    /// The smallest pressure an event may carry while still meaning "touching".
    ///
    /// Zero in a tablet event means no contact at all. The panel's lightest
    /// registering press normalises to about 0.006 — measured — so a real,
    /// deliberate touch would otherwise arrive claiming not to be one.
    static let minimumContactPressure = 0.02

    /// The pressure to put in an event, for a contact that is definitely
    /// happening.
    ///
    /// The scale is lifted off zero rather than clamped at it, so light strokes
    /// stay distinguishable from each other instead of flattening onto one
    /// minimum.
    static func eventPressure(_ normalized: Double) -> Double {
        let clamped = min(max(normalized, 0), 1)
        return minimumContactPressure + clamped * (1 - minimumContactPressure)
    }
}
