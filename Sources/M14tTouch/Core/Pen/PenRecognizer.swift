import CoreGraphics
import Foundation

/// Turns pen samples into actions (pen spec §9).
///
/// Deliberately not a `GestureRecognizer`: pen spec §4 is explicit that pen
/// input must not pass through the finger pipeline, and the two have almost
/// nothing in common. A finger has to be interpreted — was that a tap, a scroll,
/// the start of a drag? — while a pen says plainly what it is doing. There is
/// nothing to infer here, only state to track.
struct PenRecognizer: Equatable {

    /// The states pen spec §9 asks for.
    enum State: Equatable {
        case outOfRange
        case hovering
        case touching(PenTool)
    }

    private(set) var state: State = .outOfRange
    private(set) var buttons: PenButtons = []
    private var lastPosition: CGPoint = .zero

    /// Feed a sample, in order.
    mutating func process(_ sample: PenSample) -> [PenAction] {
        var actions: [PenAction] = []

        guard sample.inProximity else {
            // Out of range ends everything, in the order that leaves nothing
            // held: the contact first, then the buttons, then the proximity.
            if case .touching(let tool) = state {
                actions.append(.contactEnded(tool: tool, position: lastPosition))
            }
            if state != .outOfRange {
                if !buttons.isEmpty {
                    buttons = []
                    actions.append(.buttonsChanged([], position: lastPosition))
                }
                actions.append(.proximityExited)
            }
            state = .outOfRange
            return actions
        }

        if state == .outOfRange {
            state = .hovering
            lastPosition = sample.position
            actions.append(.proximityEntered(position: sample.position))
        }

        // Buttons before contact: holding the near button is what decides that
        // the next contact is an eraser stroke rather than a tip one, so a
        // backend seeing them in this order never has to revise.
        if sample.buttons != buttons {
            buttons = sample.buttons
            actions.append(.buttonsChanged(sample.buttons, position: sample.position))
        }

        switch (state, sample.contact) {
        case (.hovering, nil):
            if sample.position != lastPosition {
                actions.append(.hover(position: sample.position))
            }

        case (.hovering, .some(let tool)):
            state = .touching(tool)
            actions.append(.contactBegan(tool: tool, position: sample.position, pressure: sample.pressure))

        case (.touching(let tool), nil):
            state = .hovering
            actions.append(.contactEnded(tool: tool, position: sample.position))

        case (.touching(let was), .some(let now)) where was != now:
            // The tool changed without lifting — the near button pressed or
            // released mid-stroke. Ending one and beginning the other keeps the
            // backend from having to notice, and matches what the device means.
            actions.append(.contactEnded(tool: was, position: sample.position))
            state = .touching(now)
            actions.append(.contactBegan(tool: now, position: sample.position, pressure: sample.pressure))

        case (.touching(let tool), .some):
            actions.append(.contactMoved(tool: tool, position: sample.position, pressure: sample.pressure))

        case (.outOfRange, _):
            break   // handled above
        }

        lastPosition = sample.position
        return actions
    }

    /// Abandon everything, releasing whatever is held.
    ///
    /// For unplugging mid-stroke: the same duty the finger side has, since a
    /// contact that never ends leaves a button pressed with no pen to lift it.
    mutating func reset() -> [PenAction] {
        var actions: [PenAction] = []
        if case .touching(let tool) = state {
            actions.append(.contactEnded(tool: tool, position: lastPosition))
        }
        if !buttons.isEmpty {
            actions.append(.buttonsChanged([], position: lastPosition))
        }
        if state != .outOfRange {
            actions.append(.proximityExited)
        }
        state = .outOfRange
        buttons = []
        return actions
    }
}
