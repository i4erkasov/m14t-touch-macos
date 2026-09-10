import Foundation

/// Runtime configuration for the touch driver.
///
/// Populated from command-line arguments in `main.swift`. Kept as a plain
/// value type so it is trivial to construct in tests and pass around without
/// hidden state.
struct TouchConfig {

    /// Which gesture model interprets the touch stream.
    var mode: TouchMode = .mouse

    /// Which display the panel is mapped to.
    ///
    /// Defaults to automatic — the first external display — rather than a fixed
    /// index, which spec §32 forbids and which was wrong the moment a monitor
    /// was unplugged.
    var display: DisplaySelection = .automatic

    /// Mirror the horizontal axis (use if touch is flipped left↔right).
    var invertX: Bool = false

    /// Mirror the vertical axis (use if touch is flipped top↔bottom).
    var invertY: Bool = false

    /// Print every raw HID event and resulting action. Useful for calibration.
    var debugMode: Bool = false

    /// Ask macOS to show the Accessibility permission prompt when access is missing.
    var promptForAccessibility: Bool = true

    /// How gestures are interpreted. Grouped so the recognizers take one value
    /// rather than a growing list of loose numbers.
    var gestures = GestureConfiguration()

    /// When `true`, the driver widens its coordinate range as it observes touch
    /// values, then persists the result. Touch all four corners once to calibrate.
    var autoCalibrate: Bool = false

    // MARK: Manual calibration overrides

    /// Explicit raw coordinate bounds. When set, these win over both the HID
    /// descriptor values and any persisted calibration.
    var manualXMin: Double?
    var manualXMax: Double?
    var manualYMin: Double?
    var manualYMax: Double?

    /// `true` when the user supplied any manual bound on the command line.
    var hasManualCalibration: Bool {
        manualXMin != nil || manualXMax != nil || manualYMin != nil || manualYMax != nil
    }
}
