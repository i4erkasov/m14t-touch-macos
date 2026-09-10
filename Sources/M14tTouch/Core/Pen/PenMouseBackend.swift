import CoreGraphics
import Foundation

/// Where pen actions become macOS events (pen spec §19).
protocol PenEventBackend {
    func handle(_ action: PenAction)
}

/// The fallback backend from pen spec §21: pen actions as ordinary mouse events.
///
/// Called a fallback because it cannot carry pressure — a mouse event has
/// nowhere to put it — nor say that a stroke came from the eraser end. Tablet
/// events can do both and turn out to be public API, but whether applications
/// honour synthesised ones is still unmeasured, so the thing that works
/// everywhere is what ships first.
final class PenMouseBackend: PenEventBackend {

    private let poster = CGEventPoster()
    private var configuration: PenConfiguration
    private var heldButtons: PenButtons = []
    private var lastPosition: CGPoint = .zero

    /// Where the pointer was before the pen took it.
    var parking = CursorParking()

    /// Whether the near button has been held through a contact.
    ///
    /// The near button means two things and they must not both happen. Held
    /// while touching, it erases; pressed and released in the air, it performs
    /// whatever it is mapped to. So the hover action waits for the release and
    /// is cancelled the moment a contact begins — otherwise reaching to erase
    /// something would fire a secondary click on the way.
    private var nearButtonUsedForContact = false

    init(configuration: PenConfiguration = PenConfiguration()) {
        self.configuration = configuration
    }

    func apply(_ configuration: PenConfiguration) {
        // Release anything the old mapping was holding, or a button mapped away
        // mid-press would stay down with nothing left to release it.
        if heldButtons.contains(.barrel) {
            release(self.configuration.farButton, at: lastPosition)
        }
        heldButtons = []
        nearButtonUsedForContact = false
        self.configuration = configuration
    }

    func handle(_ action: PenAction) {
        if let position = action.position { lastPosition = position }

        switch action {
        case .buttonsChanged(let buttons, let position):
            handleButtons(buttons, at: position)

        case .contactBegan(let tool, _, _):
            // A contact settles what the near button meant this time.
            if tool == .eraser { nearButtonUsedForContact = true }
            emit(action)

        case .proximityExited:
            // Before anything else: the dot is taken down straight after this,
            // and the arrow underneath should reappear where the user left it
            // rather than flick across from the panel.
            if configuration.restoresPointerOnExit {
                parking.restore()
            } else {
                parking.forget()
            }

        default:
            emit(action)
        }
    }

    private func handleButtons(_ buttons: PenButtons, at position: CGPoint) {
        let farWasHeld = heldButtons.contains(.barrel)
        let farIsHeld = buttons.contains(.barrel)
        let nearWasHeld = heldButtons.contains(.eraserMode)
        let nearIsHeld = buttons.contains(.eraserMode)
        heldButtons = buttons

        if farIsHeld, !farWasHeld { press(configuration.farButton, at: position) }
        if farWasHeld, !farIsHeld { release(configuration.farButton, at: position) }

        if nearIsHeld, !nearWasHeld { nearButtonUsedForContact = false }
        if nearWasHeld, !nearIsHeld {
            // Released. If nothing was touched while it was held, it was a press
            // of a button rather than a choice of tool.
            if !nearButtonUsedForContact {
                press(configuration.nearButtonHover, at: position)
                release(configuration.nearButtonHover, at: position)
            }
            nearButtonUsedForContact = false
        }
    }

    private func emit(_ action: PenAction) {
        for event in Self.mouseEvents(
            for: action,
            eraser: configuration.nearButtonTouch,
            pointerFollowsHover: configuration.pointerFollowsHover
        ) {
            post(event.type, at: event.point)
        }
    }

    /// Every event this backend sends goes through here, so nothing can move the
    /// pointer without first remembering where it was — the button presses do
    /// not go through `emit`, and they displace it just the same.
    private func post(_ type: CGEventType, at point: CGPoint) {
        parking.rememberIfNeeded()
        poster.post(type, at: point)
    }

    // MARK: - Mapping

    /// The events an action becomes. Pure, and therefore tested.
    ///
    /// Proximity is the interesting one. Moving the pointer the moment the pen
    /// arrives is the whole fix: without it the pointer stays wherever it was —
    /// on the MacBook, most likely — and hovering over the panel drags it around
    /// a screen the pen is not near (pen spec §11).
    static func mouseEvents(
        for action: PenAction,
        eraser: PenTouchAction = .eraser,
        pointerFollowsHover: Bool = true
    ) -> [(type: CGEventType, point: CGPoint)] {
        // What an eraser stroke turns into. `eraser` is the honest answer of
        // "nothing macOS understands": applications learn about an eraser from a
        // tablet event this backend cannot send, so the stroke produces no
        // events at all rather than silently drawing with the wrong end.
        let mapping: PenButtonMapping
        switch eraser {
        case .eraser, .none: mapping = .none
        case .primaryClick:  mapping = .leftClick
        }

        switch action {
        case .proximityEntered(let position), .hover(let position):
            return pointerFollowsHover ? [(.mouseMoved, position)] : []

        case .contactBegan(.tip, let position, _):
            return [(.leftMouseDown, position)]
        case .contactMoved(.tip, let position, _):
            return [(.leftMouseDragged, position)]
        case .contactEnded(.tip, let position):
            return [(.leftMouseUp, position)]

        case .contactBegan(.eraser, let position, _):
            return down(mapping).map { [($0, position)] } ?? []
        case .contactMoved(.eraser, let position, _):
            return dragged(mapping).map { [($0, position)] } ?? []
        case .contactEnded(.eraser, let position):
            return up(mapping).map { [($0, position)] } ?? []

        case .proximityExited, .buttonsChanged:
            return []
        }
    }

    private func press(_ mapping: PenButtonMapping, at position: CGPoint) {
        guard let type = Self.down(mapping) else { return }
        post(type, at: position)
    }

    private func release(_ mapping: PenButtonMapping, at position: CGPoint) {
        guard let type = Self.up(mapping) else { return }
        post(type, at: position)
    }

    /// Down and up rather than a synthetic click pair, so holding the button
    /// holds the button — which is what a context menu expects.
    static func down(_ mapping: PenButtonMapping) -> CGEventType? {
        switch mapping {
        case .none:        return nil
        case .leftClick:   return .leftMouseDown
        case .rightClick:  return .rightMouseDown
        case .middleClick: return .otherMouseDown
        }
    }

    static func up(_ mapping: PenButtonMapping) -> CGEventType? {
        switch mapping {
        case .none:        return nil
        case .leftClick:   return .leftMouseUp
        case .rightClick:  return .rightMouseUp
        case .middleClick: return .otherMouseUp
        }
    }

    static func dragged(_ mapping: PenButtonMapping) -> CGEventType? {
        switch mapping {
        case .none:        return nil
        case .leftClick:   return .leftMouseDragged
        case .rightClick:  return .rightMouseDragged
        case .middleClick: return .otherMouseDragged
        }
    }

}
