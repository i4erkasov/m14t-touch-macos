import Foundation

/// Delivers an `InputAction` to macOS.
///
/// The seam that keeps event generation out of gesture recognition (spec §32).
/// Recognizers decide *what the user meant* and hand back values; conforming
/// types decide *how the system is told*. Tests substitute a recorder here, which
/// is the only reason gesture behaviour can be asserted at all — posted events
/// disappear into the window server and cannot be observed.
protocol EventEmitter {
    func emit(_ action: InputAction)
}
