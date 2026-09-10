import CoreGraphics

/// A physical display, identified by something that survives replugging.
///
/// An index does not: it is a position in whatever order CoreGraphics reports
/// today, so unplugging one monitor renumbers the rest and the driver starts
/// aiming at the wrong screen. Vendor, model and serial come from the display's
/// EDID and stay with the panel (spec §17).
struct DisplayIdentity: Equatable, Codable {
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32

    /// Not all displays report a serial — many return zero — so identity is the
    /// three together, and two identical models with no serial are genuinely
    /// indistinguishable this way.
    var isUsable: Bool { vendor != 0 || model != 0 || serial != 0 }

    /// How this display is named in stored calibration.
    ///
    /// Displays that identify themselves get a key of their own; the ones that
    /// cannot share a single bucket, which is honest — nothing distinguishes
    /// them, so nothing should pretend to.
    var storageKey: String {
        guard isUsable else { return "unidentified" }
        return String(format: "%04X-%04X-%08X", vendor, model, serial)
    }
}

/// Which display the panel is mapped to.
///
/// Deliberately a struct rather than an enum of alternatives: the identity is
/// what should win, the index is what remains when it cannot, and both being
/// present at once is the normal state rather than an error.
struct DisplaySelection: Equatable, Codable {

    /// The display the user chose, when it could be identified.
    var identity: DisplayIdentity?

    /// Position to fall back on. Also what `--display N` sets.
    var index: Int?

    static let automatic = DisplaySelection(identity: nil, index: nil)

    static func index(_ value: Int) -> DisplaySelection {
        DisplaySelection(identity: nil, index: value)
    }
}
