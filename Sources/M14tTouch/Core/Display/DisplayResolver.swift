import AppKit
import CoreGraphics

/// A connected display, in a form convenient for logging and selection.
struct DisplayInfo: Equatable {
    let index: Int
    let id: CGDirectDisplayID
    let bounds: CGRect
    let isMain: Bool
    let isBuiltin: Bool
    let identity: DisplayIdentity
}

extension DisplayInfo {

    /// What macOS calls this display — "M14t", not the touch interface's own
    /// name for itself.
    ///
    /// The HID product string is `Pen and multitouch sensor`, which describes an
    /// interface rather than a thing anyone owns. This is the name shown beside
    /// the monitor's picture in System Settings, and the one to put in front of
    /// a person.
    var name: String? {
        NSScreen.screens.first {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == id
        }?.localizedName
    }
}

/// Which display was chosen, and on what grounds.
struct DisplayResolution: Equatable {
    let display: DisplayInfo
    let match: Match

    enum Match: Equatable {
        /// Found the display the user picked.
        case identity
        /// Matched by position, which is all there was to go on.
        case index
        /// Nothing was asked for: the first external display, or the main one.
        case automatic
        /// What was asked for is not connected.
        case unavailable
    }
}

/// Thin wrapper over CoreGraphics' display enumeration.
///
/// Isolated so the rest of the code talks about "display index 1" rather than
/// juggling `CGDirectDisplayID` arrays everywhere.
enum DisplayResolver {

    private static let maxDisplays = 16

    /// Enumerate all active displays in CoreGraphics order.
    static func all() -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: maxDisplays)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(maxDisplays), &ids, &count)

        return (0..<Int(count)).map { i in
            DisplayInfo(
                index: i,
                id: ids[i],
                bounds: CGDisplayBounds(ids[i]),
                isMain: CGDisplayIsMain(ids[i]) != 0,
                isBuiltin: CGDisplayIsBuiltin(ids[i]) != 0,
                identity: DisplayIdentity(
                    vendor: CGDisplayVendorNumber(ids[i]),
                    model: CGDisplayModelNumber(ids[i]),
                    serial: CGDisplaySerialNumber(ids[i])
                )
            )
        }
    }

    /// Pick the display a selection refers to.
    ///
    /// Pure over the list it is given, so the precedence can be tested without
    /// monitors: **identity, then index, then the first external display**.
    ///
    /// External first, because the panel this driver exists for is by definition
    /// not the built-in screen, and because spec §32 forbids the hardcoded index
    /// that used to stand here.
    static func resolve(_ selection: DisplaySelection, among displays: [DisplayInfo]) -> DisplayResolution? {
        guard let fallback = displays.first(where: { !$0.isBuiltin }) ?? displays.first else {
            return nil
        }

        if let identity = selection.identity, identity.isUsable {
            if let match = displays.first(where: { $0.identity == identity }) {
                return DisplayResolution(display: match, match: .identity)
            }
            // Asked for a display that is not here. Say so rather than silently
            // aiming somewhere else — spec §30 expects a reconnect to restore the
            // old target, and quietly picking a different screen hides that it
            // did not.
            return DisplayResolution(display: fallback, match: .unavailable)
        }

        if let index = selection.index {
            if let match = displays.first(where: { $0.index == index }) {
                return DisplayResolution(display: match, match: .index)
            }
            return DisplayResolution(display: fallback, match: .unavailable)
        }

        return DisplayResolution(display: fallback, match: .automatic)
    }

    /// The same, against the displays connected right now.
    static func resolve(_ selection: DisplaySelection) -> DisplayResolution? {
        resolve(selection, among: all())
    }

}
