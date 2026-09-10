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

    /// Thresholds, delays and cursor policy.
    var gestures = GestureConfiguration()

    /// Index of the display the panel is mapped to.
    ///
    /// An index is a poor identity — it shifts when displays are plugged in or
    /// rearranged — and spec §17 asks for the same display to be found again on
    /// reconnect. Step 2 of v0.3 replaces this; it is stored now so the value
    /// has somewhere to live.
    var displayIndex: Int = 1

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
        gestures = value(.gestures, fallback.gestures)
        displayIndex = value(.displayIndex, fallback.displayIndex)
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
        config.gestures = gestures
        config.displayIndex = displayIndex
        config.invertX = invertX
        config.invertY = invertY
        return config
    }
}
