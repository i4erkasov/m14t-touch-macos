import Foundation

/// Derives a coordinate range from a HID descriptor's elements.
///
/// Split out from the IOKit call so the selection rule can be tested — and it
/// needs testing, because a descriptor advertises the same usage more than once
/// and picking the wrong one puts every touch in the wrong place.
enum DescriptorRange {

    /// One descriptor element, reduced to what the range decision needs.
    struct Element: Equatable {
        let usagePage: UInt32
        let usage: UInt32
        let logicalMin: Int
        let logicalMax: Int
    }

    /// The **first** Generic Desktop X and Y in descriptor order.
    ///
    /// First, not last, and that is the whole point. The M14t's touch interface
    /// declares X three times — once in the touch collection, again in the pen
    /// collection, and again in a vendor-specific page — with different logical
    /// ranges each time. Reading them all and keeping the last yielded
    /// `0…30931`, while the panel never reports above `12288`; the first
    /// declaration says `0…12372`, which fits the observed data.
    ///
    /// Still a heuristic: descriptor order is not a promise about which
    /// collection is the touch one. It is a better guess than the previous
    /// last-wins, and it stops mattering once a calibration is saved, since
    /// that takes precedence (spec §16 replaces this model in v0.4 anyway).
    static func range(from elements: [Element]) -> CalibrationData {
        var range = CalibrationData.identity
        var haveX = false
        var haveY = false

        for element in elements where element.usagePage == HID.Page.genericDesktop.rawValue {
            switch element.usage {
            case HID.GenericDesktop.x.rawValue where !haveX:
                range.xMin = Double(element.logicalMin)
                range.xMax = Double(element.logicalMax)
                haveX = true
            case HID.GenericDesktop.y.rawValue where !haveY:
                range.yMin = Double(element.logicalMin)
                range.yMax = Double(element.logicalMax)
                haveY = true
            default:
                break
            }
            if haveX, haveY { break }
        }

        return range
    }
}
