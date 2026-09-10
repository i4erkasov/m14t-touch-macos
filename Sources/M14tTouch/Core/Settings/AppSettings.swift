import Foundation

/// What the user has chosen, as opposed to what the hardware reports.
///
/// Kept apart from `CalibrationData` on purpose (spec §21): calibration
/// describes a particular panel and is discovered, these are preferences and are
/// decided. Mixing them would mean resetting a preference to recalibrate, or
/// losing a calibration by changing a preference.
struct AppSettings: Equatable, Codable {

    /// Whether touch input is being translated at all — the menu's "Enable
    /// touch" (spec §13).
    ///
    /// Read by the app, ignored by the CLI: running the binary is itself the
    /// instruction to run, and refusing because a stored preference says
    /// otherwise would be surprising. It lives here because it is a user choice
    /// the GUI persists, not because the driver consults it.
    var enabled: Bool = true

    /// Which gesture model interprets the touch stream.
    var mode: TouchMode = .mouse

    /// Handle the stylus ourselves.
    ///
    /// Switching this on takes the device away from macOS exclusively, which is
    /// the only way to stop it moving the pointer relative to wherever it
    /// already is — hovering over the panel otherwise drags the pointer around
    /// whichever screen it was left on (`M14t_PEN_CAPABILITIES.md`).
    ///
    /// The cost is that seizing takes the *whole* device, so the pen stops
    /// working entirely when the driver is not running, where today it works
    /// badly. Worth it, but worth saying.
    var penEnabled: Bool = true

    /// Thresholds, delays and cursor policy.
    var gestures = GestureConfiguration()

    /// What the stylus's button and eraser do.
    var pen = PenConfiguration()

    /// Which display the panel is mapped to, by identity where possible so it
    /// is found again after replugging (spec §17).
    var display: DisplaySelection = .automatic

    var invertX: Bool = false
    var invertY: Bool = false

    /// Decoded field by field, each falling back to its default, so a setting
    /// added in a later version cannot make an older file undecodable and wipe
    /// the rest. See the note on `GestureConfiguration.init(from:)`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings()

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
        }

        enabled = value(.enabled, fallback.enabled)
        mode = value(.mode, fallback.mode)
        penEnabled = value(.penEnabled, fallback.penEnabled)
        gestures = value(.gestures, fallback.gestures)
        pen = value(.pen, fallback.pen)
        display = value(.display, fallback.display)
        invertX = value(.invertX, fallback.invertX)
        invertY = value(.invertY, fallback.invertY)
    }

    init() {}
}

extension AppSettings {

    /// The runtime configuration these settings describe.
    ///
    /// `TouchConfig` also carries things that are not preferences — debug
    /// logging, the Accessibility prompt, manual calibration overrides — which
    /// is why the two are separate types rather than one.
    var touchConfig: TouchConfig {
        var config = TouchConfig()
        config.mode = mode
        config.penEnabled = penEnabled
        config.gestures = gestures
        config.pen = pen
        config.display = display
        config.invertX = invertX
        config.invertY = invertY
        return config
    }
}
