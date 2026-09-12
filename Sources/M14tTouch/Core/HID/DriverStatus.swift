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

    /// Why there is no connection, when the reason is something the user could
    /// act on rather than an unplugged cable.
    ///
    /// Without this the interface can only say "Not connected", which is the
    /// same sentence for a panel that is absent, a permission that was never
    /// granted and a device another process is holding — three problems with
    /// three different answers.
    var failure: String?

    /// The touch surface's width divided by its height, from the HID
    /// descriptor.
    ///
    /// A display with different proportions cannot be the panel: mapping a
    /// 16:9 digitizer onto a 21:9 screen would scale horizontal and vertical
    /// movement differently, which is not a worse guess but an impossible one.
    var touchAspectRatio: Double?

    /// `2D1F:524C`, or nil when nothing is connected. For the diagnostics pane,
    /// where the point is to be able to read the numbers out to someone.
    var identifiers: String? {
        guard let vendorID, let productID else { return nil }
        return String(format: "%04X:%04X", vendorID, productID)
    }
}
