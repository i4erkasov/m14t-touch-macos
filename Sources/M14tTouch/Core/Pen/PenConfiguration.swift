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
        farButton = value(.farButton, fallback.farButton)
        nearButtonHover = value(.nearButtonHover, fallback.nearButtonHover)
        nearButtonTouch = value(.nearButtonTouch, fallback.nearButtonTouch)
    }

    init() {}
}
