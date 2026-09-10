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
