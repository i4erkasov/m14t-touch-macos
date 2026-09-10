import Foundation

/// Whether a HID element belongs to the pen or the finger.
///
/// The M14t is one device with two collections rather than two devices, so this
/// cannot be answered by asking which device sent a value — it has to come from
/// the collection the element sits in (`M14t_PEN_CAPABILITIES.md`).
enum InputSource: Equatable {
    case finger
    case pen

    /// Something the driver has no use for: the vendor-specific mirrors of the
    /// pen collection, device configuration, and a `Mouse / Pointer` collection
    /// that never sends anything.
    case other

    /// Classify from the chain of collections an element sits in, outermost
    /// first.
    ///
    /// Pure, so the classification can be tested against the real descriptor's
    /// shape without a device attached.
    static func from(collections: [(page: UInt32, usage: UInt32)]) -> InputSource {
        for collection in collections where collection.page == HID.Page.digitizer.rawValue {
            switch collection.usage {
            case HID.Digitizer.pen.rawValue, HID.Digitizer.stylus.rawValue:
                return .pen
            case HID.Digitizer.finger.rawValue:
                return .finger
            default:
                continue
            }
        }
        return .other
    }
}
