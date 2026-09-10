import CoreGraphics
import Foundation

/// Gathers one sample per target from a stream of touch frames (spec §15).
///
/// A target is taken when the finger lifts, using the mean of the raw positions
/// reported while it was down — a lift wobbles, and averaging costs nothing.
///
/// Crooked touches are not rejected here. The solver reports how badly the
/// samples fit and the verification screen shows the result, which is a better
/// feedback loop than arguing with the user about one target: they see what they
/// got and redo the set.
struct CalibrationCollector: Equatable {

    /// Where the targets sit, as fractions of the display.
    ///
    /// Inset from the edges because a target in the very corner is half
    /// off-screen and cannot be touched accurately. The solver extrapolates back
    /// out to the edges, which is the whole reason it fits a line.
    static let defaultTargets: [CGPoint] = [
        CGPoint(x: 0.12, y: 0.12),
        CGPoint(x: 0.88, y: 0.12),
        CGPoint(x: 0.88, y: 0.88),
        CGPoint(x: 0.12, y: 0.88),
    ]

    let targets: [CGPoint]
    private(set) var samples: [CalibrationSample] = []

    /// Raw positions seen during the contact in progress.
    private var contact: [CGPoint] = []

    init(targets: [CGPoint] = defaultTargets) {
        self.targets = targets
    }

    /// The target the user should be touching, or `nil` when every one is done.
    var currentTarget: CGPoint? {
        samples.count < targets.count ? targets[samples.count] : nil
    }

    var isComplete: Bool { samples.count == targets.count }

    /// Feed a frame.
    ///
    /// - Returns: `true` when this frame completed a target, so the caller knows
    ///   to move the marker on.
    @discardableResult
    mutating func process(_ frame: TouchFrame) -> Bool {
        guard let target = currentTarget, let point = frame.primaryContact else { return false }

        guard point.isTouching else {
            // A release with nothing recorded is not a touch on this target —
            // most often the tail of the contact that dismissed the previous one.
            guard !contact.isEmpty else { return false }
            let mean = CGPoint(
                x: contact.map(\.x).reduce(0, +) / Double(contact.count),
                y: contact.map(\.y).reduce(0, +) / Double(contact.count)
            )
            samples.append(CalibrationSample(target: target, raw: mean))
            contact = []
            return true
        }

        contact.append(point.rawPosition)
        return false
    }

    /// Throw away everything and start from the first target.
    mutating func restart() {
        samples = []
        contact = []
    }

    /// What the collected samples say, once they are all in.
    func solve() -> CalibrationResult? {
        guard isComplete else { return nil }
        return CalibrationSolver.solve(samples)
    }
}
