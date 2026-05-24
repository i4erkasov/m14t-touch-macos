import Foundation

/// The raw coordinate range a touch panel actually reports.
///
/// The M14t advertises a logical range of `0…32767` in its HID descriptor but
/// only emits values within a much narrower band. Mapping must use the *real*
/// observed range or touches land in the wrong place, so we capture and persist
/// these four numbers.
struct CalibrationData: Codable, Equatable {
    var xMin: Double
    var xMax: Double
    var yMin: Double
    var yMax: Double

    /// A neutral full-range default used before any calibration exists.
    static let identity = CalibrationData(xMin: 0, xMax: 32767, yMin: 0, yMax: 32767)
}

/// Reads and writes calibration to `~/.m14ttouch.json`.
///
/// Kept deliberately tiny and dependency-free: calibration is just four numbers,
/// so a single JSON file is the simplest thing that survives reboots and is
/// trivial for a user to inspect or hand-edit.
enum CalibrationStore {

    /// Location of the persisted calibration file.
    static let url: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".m14ttouch.json")

    /// Load saved calibration, or `nil` if none exists / the file is unreadable.
    static func load() -> CalibrationData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CalibrationData.self, from: data)
    }

    /// Persist calibration atomically. Failures are silent by design — a missed
    /// save simply means recalibrating next launch, never a crash.
    static func save(_ calibration: CalibrationData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(calibration) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Delete the saved calibration file.
    @discardableResult
    static func reset() -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }
}
