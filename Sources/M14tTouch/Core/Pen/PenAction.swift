import CoreGraphics

/// What the pen did, in terms a backend can act on (pen spec §20).
///
/// The same separation the finger side uses: recognition decides what happened,
/// something else decides how macOS is told. Raw HID never reaches an event.
enum PenAction: Equatable {

    /// The pen came within range. Nothing has been touched yet, but the pointer
    /// should already move to it — this is the moment the spec §11 cares about,
    /// where the pointer belongs on the panel rather than wherever it was left.
    case proximityEntered(position: CGPoint)

    /// The pen went away. Any contact has already been ended.
    case proximityExited

    /// Moved while not touching.
    case hover(position: CGPoint)

    /// A tip or eraser touched down.
    case contactBegan(tool: PenTool, position: CGPoint, pressure: Double?)

    /// Moved while touching.
    case contactMoved(tool: PenTool, position: CGPoint, pressure: Double?)

    /// Lifted.
    case contactEnded(tool: PenTool, position: CGPoint)

    /// A button changed. `buttons` carries the ones now held, so a backend can
    /// act on combinations without tracking state of its own.
    case buttonsChanged(PenButtons, position: CGPoint)
}

extension PenAction {

    /// Where on screen the action happened, or nil for the one action that has
    /// no place — the pen leaving.
    ///
    /// On the action rather than on a backend because more than one thing needs
    /// it now: the mouse backend, to remember where a button was pressed, and
    /// the drawn pointer, to know where to put itself.
    var position: CGPoint? {
        switch self {
        case .proximityEntered(let p), .hover(let p),
             .contactBegan(_, let p, _), .contactMoved(_, let p, _),
             .contactEnded(_, let p), .buttonsChanged(_, let p):
            return p
        case .proximityExited:
            return nil
        }
    }
}
