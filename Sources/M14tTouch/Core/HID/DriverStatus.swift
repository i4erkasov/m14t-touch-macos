import Foundation

/// What the driver can tell the interface about the hardware.
///
/// A value rather than a reference so it can cross from the touch queue to the
/// main one without anything shared being mutated on both sides (spec §25).
struct DriverStatus: Equatable {
    var isConnected: Bool = false
    var deviceName: String?
    var vendorID: Int?
    var productID: Int?

    /// `2D1F:524C`, or nil when nothing is connected. For the diagnostics pane,
    /// where the point is to be able to read the numbers out to someone.
    var identifiers: String? {
        guard let vendorID, let productID else { return nil }
        return String(format: "%04X:%04X", vendorID, productID)
    }
}
