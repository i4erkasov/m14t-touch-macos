import Foundation

/// What a pen button or the eraser does (pen spec §24).
///
/// A deliberately short list. The spec sketches a dozen possibilities —
/// modifiers, undo, keyboard shortcuts, pan — and §30 says a control appears
/// only when it changes runtime behaviour. These three are the ones that work
/// through the mouse fallback today; the rest wait for a backend that can carry
/// them.
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

/// How the stylus behaves.
struct PenConfiguration: Equatable, Codable {

    /// The button furthest from the tip — the only one free to be mapped.
    ///
    /// Secondary click by default: it is the mapping pen spec §25 proposes, and
    /// the one worth having, since both buttons work while merely hovering, so a
    /// context menu can be opened without touching the screen at all.
    var barrelButton: PenButtonMapping = .rightClick

    /// What a stroke of the eraser end does.
    ///
    /// Nothing by default, and that is not indecision. There is no gesture in
    /// macOS that means "erase"; applications that support one learn it from a
    /// tablet event carrying an eraser pointer type, which the mouse fallback
    /// cannot send. Until the tablet backend is proven, the honest options are
    /// to do nothing or to behave like the tip, and doing nothing is less
    /// surprising than silently drawing with the wrong end.
    var eraser: PenButtonMapping = .none

    /// Decoded field by field so a mapping added later cannot make an older
    /// saved file undecodable — the same reason the other settings do it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = PenConfiguration()
        barrelButton = (try? container.decodeIfPresent(PenButtonMapping.self, forKey: .barrelButton))
            .flatMap { $0 } ?? fallback.barrelButton
        eraser = (try? container.decodeIfPresent(PenButtonMapping.self, forKey: .eraser))
            .flatMap { $0 } ?? fallback.eraser
    }

    init() {}
}
