import Foundation

/// Decides when the pointer should be hidden, and keeps that decision balanced.
///
/// Sits between `TouchEngine` and whichever `CursorVisibility` is in force, so
/// the engine says only "a finger is down" or "it is not" and never learns which
/// implementation — public or private — is answering.
///
/// Hiding is asserted on every frame while a contact exists, because a single
/// request does not hold. It is released once, on the frame the contact ends.
final class CursorVisibilityController {

    private let visibility: CursorVisibility

    /// Guards the policy and the hiding flag. The policy is changed from the
    /// settings window on the main thread while the touch queue reads it on
    /// every frame.
    private let lock = NSLock()
    private var policy: CursorHiding
    private var isHiding = false

    /// The two things that independently want the pointer gone.
    ///
    /// Kept apart and combined rather than sharing one flag, because either can
    /// stop wanting it while the other still does — a finger lifting during a
    /// pen stroke would otherwise give the arrow back on top of the dot. The
    /// underlying `release()` undoes every assertion at once, so there can only
    /// be one caller of it, and this is it.
    private var fingerWantsHiding = false
    private var penWantsHiding = false
    private var glideWantsHiding = false

    init(policy: CursorHiding, visibility: CursorVisibility) {
        self.policy = policy
        self.visibility = visibility
    }

    /// Change when hiding applies, from any thread.
    ///
    /// Gives the pointer back when hiding is switched off, rather than leaving
    /// it hidden until the next release that will now never come.
    func setPolicy(_ replacement: CursorHiding) {
        lock.lock()
        let changed = replacement != policy
        policy = replacement
        lock.unlock()

        guard changed else { return }
        restore()
    }

    /// Whether hiding will actually happen — asked for *and* supported.
    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return policy.hidesAnything && visibility.isAvailable
    }

    /// Follow the latest frame.
    ///
    /// - Parameter isScrolling: whether the gesture has committed to scrolling.
    ///   Only meaningful for the `.scrolling` policy.
    func update(isTouching: Bool, isScrolling: Bool) {
        settle {
            let active = self.policy.hidesAnything && self.visibility.isAvailable
            switch self.policy {
            case .never:     self.fingerWantsHiding = false
            case .scrolling: self.fingerWantsHiding = active && isTouching && isScrolling
            case .touching:  self.fingerWantsHiding = active && isTouching
            }
        }
    }

    /// Follow the glide that carries on after a finger lifts.
    ///
    /// Without this the arrow reappeared the instant the finger left and then
    /// sat there while the content was still moving — the one moment it is most
    /// obviously in the way, since nothing is touching the screen to explain it.
    ///
    /// Subject to the hiding policy, unlike the pen's: a glide is the tail of a
    /// scroll, so whoever asked not to have the pointer hidden while scrolling
    /// did not ask for this either.
    func updateGlide(isRunning: Bool) {
        settle {
            self.glideWantsHiding = isRunning
                && self.policy.hidesAnything
                && self.visibility.isAvailable
        }
    }

    /// Follow the pen's own pointer.    /// Follow the pen's own pointer.
    ///
    /// Independent of the hiding policy, which is about fingers: a drawn pointer
    /// is not a policy about when to hide the arrow, it is a replacement for it,
    /// and leaving both on screen would be the one outcome nobody asked for.
    ///
    /// Called once per pen sample while the dot is up, for the same reason the
    /// finger path is: the window server does not honour a single request.
    func updatePenPointer(isDrawn: Bool) {
        settle { self.penWantsHiding = isDrawn && self.visibility.isAvailable }
    }

    /// Apply a change to what is wanted, then make the world match it.
    ///
    /// The CoreGraphics calls are made outside the lock: they reach into the
    /// window server, and holding a lock across that would put it on the
    /// critical path of every frame.
    private func settle(_ change: () -> Void) {
        lock.lock()
        change()
        let wanted = fingerWantsHiding || penWantsHiding || glideWantsHiding
        let shouldRelease = !wanted && isHiding
        isHiding = wanted
        lock.unlock()

        if wanted {
            visibility.assertHidden()
        } else if shouldRelease {
            visibility.release()
        }
    }

    /// Give the pointer back unconditionally.
    ///
    /// Called on shutdown and when the device disappears. Deliberately does not
    /// check `isHiding`: the point is to leave nothing hidden, and releasing
    /// when nothing is held costs nothing.
    func restore() {
        lock.lock()
        isHiding = false
        fingerWantsHiding = false
        penWantsHiding = false
        glideWantsHiding = false
        lock.unlock()
        visibility.release()
    }
}
