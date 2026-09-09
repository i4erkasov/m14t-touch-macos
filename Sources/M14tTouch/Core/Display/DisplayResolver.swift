import CoreGraphics

/// A connected display, in a form convenient for logging and selection.
struct DisplayInfo {
    let index: Int
    let id: CGDirectDisplayID
    let bounds: CGRect
    let isMain: Bool
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
                isMain: CGDisplayIsMain(ids[i]) != 0
            )
        }
    }

    /// Resolve the bounds for a requested display index.
    ///
    /// Falls back to the main display if the index is out of range, returning
    /// the index actually used so the caller can warn the user.
    static func bounds(forIndex index: Int) -> (bounds: CGRect, resolvedIndex: Int) {
        let displays = all()
        guard !displays.isEmpty else { return (.zero, 0) }
        if index >= 0, index < displays.count {
            return (displays[index].bounds, index)
        }
        return (displays[0].bounds, 0)
    }
}
