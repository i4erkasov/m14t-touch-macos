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
        lock.lock()
        let active = policy.hidesAnything && visibility.isAvailable
        let wanted: Bool
        switch policy {
        case .never:     wanted = false
        case .scrolling: wanted = active && isTouching && isScrolling
        case .touching:  wanted = active && isTouching
        }
        let shouldRelease = !wanted && isHiding
        isHiding = wanted
        lock.unlock()

        // The calls themselves are made outside the lock: they reach into
        // CoreGraphics, and holding a lock across that would put the window
        // server on the critical path of every frame.
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
        lock.unlock()
        visibility.release()
    }
}
