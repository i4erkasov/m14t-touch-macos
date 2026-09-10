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
