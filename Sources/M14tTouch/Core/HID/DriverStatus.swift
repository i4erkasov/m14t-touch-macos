import Foundation

/// What the driver can tell the interface about the hardware.
///
/// A value rather than a reference so it can cross from the touch queue to the
/// main one without anything shared being mutated on both sides (spec §25).
struct DriverStatus: Equatable {
    var isConnected: Bool = false
    var deviceName: String?
}
