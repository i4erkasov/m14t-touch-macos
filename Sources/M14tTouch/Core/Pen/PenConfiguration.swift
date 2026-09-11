import Foundation

/// What a pen button does (pen spec §24).
///
/// A deliberately short list. The spec sketches a dozen possibilities —
/// modifiers, undo, keyboard shortcuts, pan — and §30 says a control appears
/// only when it changes runtime behaviour. These are the ones that work through
/// the mouse fallback today; the rest wait for a backend that can carry them.
enum PenButtonMapping: String, CaseIterable, Codable {
    case none
    case leftClick
    case rightClick
    case middleClick

    var title: String {
        switch self {
        case .none:        return "Nothing"
        case .leftClick:   return "Primary click"
        case .rightClick:  return "Secondary click"
        case .middleClick: return "Middle click"
        }
    }
}

/// What the near button does when the pen is also touching the screen.
enum PenTouchAction: String, CaseIterable, Codable {
    /// What the hardware itself does: the panel reports an eraser stroke rather
    /// than a tip one.
    case eraser
    /// Treat it as an ordinary stroke, indistinguishable from the tip.
    case primaryClick
    case none

    var title: String {
        switch self {
        case .eraser:       return "Eraser"
        case .primaryClick: return "Primary click"
        case .none:         return "Nothing"
        }
    }
}

/// How the stylus behaves.
///
/// Described in terms of the two buttons a user can see and press. The panel
/// expresses the near one through `Invert` and `Eraser` rather than as a button,
/// but that is the driver's problem, not the reader's.
struct PenConfiguration: Equatable, Codable {

    /// Move the pointer to the pen while it hovers, before it touches anything.
    ///
    /// On by default: seeing where the pen is about to land is most of what
    /// hovering is for. Turning it off leaves the pointer alone until the pen
    /// actually touches.
    var pointerFollowsHover: Bool = true

    /// What the user sees following the pen.
    ///
    /// The arrow by default, because the alternative depends on being able to
    /// hide the system pointer, and that needs the private call the amendment
    /// allows — which may be unavailable. Choosing the dot when nothing can be
    /// hidden would put two pointers on screen, so the honest default is the
    /// behaviour that always works.
    var pointer: PenPointerStyle = .arrow

    /// How big the drawn dot is, in points.
    var pointerSize: Double = 14

    /// The colour of the ring around the drawn dot.
    ///
    /// The ring rather than the middle: the dot's core stays dark so it can be
    /// seen against a pale window, and the ring carries the colour and the
    /// contrast against a dark one. Colouring the core instead would make the
    /// pointer disappear over anything of a similar shade.
    var pointerColor: RGBAColor = .systemGreen

    /// Put the pointer back where it was when the pen leaves the panel.
    ///
    /// Reaching the panel means taking the pointer there — a click carries its
    /// position — and leaving it parked on a touchscreen is not where the user
    /// left it. The finger side already does this at the end of a gesture; for
    /// the pen the equivalent moment is losing proximity.
    ///
    /// Nothing is returned if nothing was taken: the pointer is remembered at
    /// the first move, so a pen that only hovered with hover-following off
    /// moves nothing on the way out either.
    var restoresPointerOnExit: Bool = true

    /// Tell applications how hard the pen is being pressed.
    ///
    /// Measured to work at the event level: an event marked as a tablet point
    /// arrives with its pressure intact, where an ordinary mouse event carries
    /// only 1 or 0 (`docs/M14t_PEN_CAPABILITIES.md`).
    ///
    /// **Off by default, and that is not caution — it is a finding.** Marking
    /// events as tablet points was tried on by default and broke a real
    /// application: in a browser-based paint program the pen stopped working
    /// mid-stroke and stayed broken after the button was released. The
    /// assumption behind the default — that an application which does not
    /// understand tablets would ignore the marking and see the click it always
    /// saw — is false for at least one real consumer. Whatever the mechanism,
    /// this changes what *every* application receives, and something that can
    /// break the pen must be asked for rather than assumed.
    ///
    /// What it cannot do at all is say *which end* of the pen is touching: the
    /// proximity event that would carry that never reaches applications.
    var sendsPressure: Bool = false

    /// Ignore finger touches while the pen is near the panel (pen spec §15).
    ///
    /// A hand resting on the screen to write with is the case this exists for.
    /// Only new contacts are ignored — a finger already down when the pen
    /// arrives keeps its gesture rather than having it cut in half.
    var palmRejection: Bool = true

    /// The button furthest from the tip.
    ///
    /// Secondary click by default, as pen spec §25 proposes, and worth having
    /// because both buttons work while merely hovering — a context menu without
    /// touching the screen at all.
    var farButton: PenButtonMapping = .rightClick

    /// The near button, pressed and released without touching the screen.
    ///
    /// Acts on release rather than on press, and only when no contact happened
    /// in between. Otherwise reaching to erase something would fire this first
    /// and the eraser stroke second, which is not what anyone means by holding a
    /// button and drawing.
    var nearButtonHover: PenButtonMapping = .rightClick

    /// The near button, held while the pen touches the screen.
    var nearButtonTouch: PenTouchAction = .eraser

    /// Decoded field by field so a mapping added later cannot make an older
    /// saved file undecodable — the same reason the other settings do it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = PenConfiguration()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
        }
        pointerFollowsHover = value(.pointerFollowsHover, fallback.pointerFollowsHover)
        palmRejection = value(.palmRejection, fallback.palmRejection)
        pointer = value(.pointer, fallback.pointer)
        pointerSize = value(.pointerSize, fallback.pointerSize)
        pointerColor = value(.pointerColor, fallback.pointerColor)
        restoresPointerOnExit = value(.restoresPointerOnExit, fallback.restoresPointerOnExit)
        sendsPressure = value(.sendsPressure, fallback.sendsPressure)
        farButton = value(.farButton, fallback.farButton)
        nearButtonHover = value(.nearButtonHover, fallback.nearButtonHover)
        nearButtonTouch = value(.nearButtonTouch, fallback.nearButtonTouch)
    }

    init() {}
}
