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

    /// How much charge the stylus reports, 0…1, or nil until it has said.
    ///
    /// Worth carrying here rather than only in the live diagnostics, because
    /// this is the number that explains the failure this project has actually
    /// hit: a pen that stops transmitting looks exactly like a broken driver,
    /// and only the battery tells them apart. Silent until the pen reports —
    /// a level invented before one arrives would be worse than none.
    var batteryLevel: Double?

    /// The touch surface's width divided by its height, from the HID
    /// descriptor.
    ///
    /// A display with different proportions cannot be the panel: mapping a
    /// 16:9 digitizer onto a 21:9 screen would scale horizontal and vertical
    /// movement differently, which is not a worse guess but an impossible one.
    var touchAspectRatio: Double?

    /// The charge as a percentage, for showing to a person.
    var batteryPercentage: Int? {
        batteryLevel.map { Int(($0 * 100).rounded()) }
    }

    /// The SF Symbol that matches that charge.
    ///
    /// Five steps, which is what the symbol set offers; rounding to the nearest
    /// keeps a nearly-full battery from being drawn three-quarters empty.
    var batterySymbol: String? {
        guard let percentage = batteryPercentage else { return nil }
        switch percentage {
        case ..<13:  return "battery.0"
        case ..<38:  return "battery.25"
        case ..<63:  return "battery.50"
        case ..<88:  return "battery.75"
        default:     return "battery.100"
        }
    }

    /// Whether the charge is low enough to be worth mentioning unprompted.
    ///
    /// The threshold exists because of how this hardware fails: the stylus
    /// stops transmitting altogether, with no warning and no obvious cause, and
    /// an afternoon went into diagnosing that once.
    var isBatteryLow: Bool {
        (batteryPercentage ?? 100) <= 20
    }

    /// `2D1F:524C`, or nil when nothing is connected. For the diagnostics pane,
    /// where the point is to be able to read the numbers out to someone.
    var identifiers: String? {
        guard let vendorID, let productID else { return nil }
        return String(format: "%04X:%04X", vendorID, productID)
    }
}
