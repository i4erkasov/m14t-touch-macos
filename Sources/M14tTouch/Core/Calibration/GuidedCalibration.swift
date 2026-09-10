import CoreGraphics
import Foundation

/// Drives the guided calibration flow (spec §15): touch four targets, then check
/// the result before keeping it.
///
/// Kept free of AppKit so the whole sequence — including which button a finger
/// landed on — can be tested without opening a window.
struct GuidedCalibration: Equatable {

    enum Phase: Equatable {
        /// Touching targets, one at a time.
        case aiming

        /// The result is in force; move a finger and see whether the marker
        /// follows it, then keep or redo.
        case verifying(CalibrationResult)

        /// The samples said nothing usable — every target in a line, or a panel
        /// that reported one value throughout.
        case unusable

        /// Finished, one way or the other.
        case finished(CalibrationResult?)
    }

    /// Where the verification buttons sit, as fractions of the display.
    ///
    /// Shared between drawing and hit-testing rather than written twice, so a
    /// finger cannot land somewhere the button is not.
    enum Button: CaseIterable {
        case save
        case retry

        var rect: CGRect {
            switch self {
            case .save:  return CGRect(x: 0.30, y: 0.62, width: 0.16, height: 0.09)
            case .retry: return CGRect(x: 0.54, y: 0.62, width: 0.16, height: 0.09)
            }
        }
    }

    private(set) var phase: Phase = .aiming
    private(set) var collector = CalibrationCollector()

    /// Where the finger is, as a fraction of the display, once there is a
    /// calibration to judge it by. `nil` when nothing is touching.
    private(set) var marker: CGPoint?

    var currentTarget: CGPoint? { collector.currentTarget }

    /// Feed a frame. Returns the button a touch just pressed, if any.
    @discardableResult
    mutating func handle(_ frame: TouchFrame) -> Button? {
        switch phase {
        case .aiming:
            collector.process(frame)
            guard collector.isComplete else { return nil }
            phase = collector.solve().map(Phase.verifying) ?? .unusable
            return nil

        case .verifying(let result):
            guard let contact = frame.primaryContact else { return nil }
            let position = result.fraction(of: contact.rawPosition)

            guard contact.isTouching else {
                marker = nil
                // Pressed on release, not on contact, so a finger that lands on
                // a button and slides off does not press it.
                return Button.allCases.first { $0.rect.contains(position) }
            }
            marker = position
            return nil

        case .unusable, .finished:
            return nil
        }
    }

    mutating func press(_ button: Button) {
        guard case .verifying(let result) = phase else { return }
        switch button {
        case .save:  phase = .finished(result)
        case .retry: retry()
        }
    }

    mutating func retry() {
        collector.restart()
        marker = nil
        phase = .aiming
    }

    mutating func cancel() {
        phase = .finished(nil)
    }
}
