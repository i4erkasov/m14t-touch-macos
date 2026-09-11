import CoreGraphics
import Foundation

/// The glide after a flick.
///
/// macOS generates this itself for a trackpad; for a panel driven from user
/// space there is nothing to generate it, so the deceleration is produced here
/// — a velocity at the moment the finger left, decayed a little on every tick
/// until it is too slow to see.
///
/// A value type with no timer in it, because the arithmetic is the part worth
/// testing and a timer is the part that cannot be.
struct ScrollMomentum: Equatable {

    /// Points per second at the moment of release.
    private(set) var velocity: CGVector

    /// How much of the speed survives each tick.
    ///
    /// At 60 ticks a second, 0.95 leaves about 5% of the original speed after
    /// one second — a glide that is clearly a glide and clearly over. Faster
    /// decay feels like friction; slower feels like ice.
    let decay: Double

    /// Below this, in points per second, the movement is finished. Not zero:
    /// an exponential decay never reaches zero, and a tick that moves less than
    /// a pixel is a tick nobody can see.
    let minimumSpeed: Double

    /// Seconds between ticks.
    let interval: TimeInterval

    init(
        velocity: CGVector,
        decay: Double = 0.95,
        minimumSpeed: Double = 40,
        interval: TimeInterval = 1.0 / 60
    ) {
        self.velocity = velocity
        self.decay = decay
        self.minimumSpeed = minimumSpeed
        self.interval = interval
    }

    /// Current speed, regardless of direction.
    var speed: Double {
        Double(hypot(velocity.dx, velocity.dy))
    }

    /// Whether a flick this fast is worth continuing at all.
    ///
    /// A slow drag that simply stops should stop, not drift on for another
    /// second — the finger was placing the content, not throwing it.
    var isWorthGliding: Bool { speed >= minimumSpeed }

    /// The distance to scroll for this tick, or nil once the glide is over.
    mutating func next() -> CGVector? {
        guard speed >= minimumSpeed else { return nil }

        let step = CGVector(
            dx: velocity.dx * CGFloat(interval),
            dy: velocity.dy * CGFloat(interval)
        )
        velocity = CGVector(
            dx: velocity.dx * CGFloat(decay),
            dy: velocity.dy * CGFloat(decay)
        )
        return step
    }
}
