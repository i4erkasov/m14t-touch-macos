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
    private let policy: CursorHiding
    private var isHiding = false

    init(policy: CursorHiding, visibility: CursorVisibility) {
        self.policy = policy
        self.visibility = visibility
    }

    /// Whether hiding will actually happen — asked for *and* supported.
    var isActive: Bool { policy.hidesAnything && visibility.isAvailable }

    /// Follow the latest frame.
    ///
    /// - Parameter isScrolling: whether the gesture has committed to scrolling.
    ///   Only meaningful for the `.scrolling` policy.
    func update(isTouching: Bool, isScrolling: Bool) {
        guard isActive else { return }

        let wanted: Bool
        switch policy {
        case .never:     wanted = false
        case .scrolling: wanted = isTouching && isScrolling
        case .touching:  wanted = isTouching
        }

        if wanted {
            isHiding = true
            visibility.assertHidden()
        } else if isHiding {
            isHiding = false
            visibility.release()
        }
    }

    /// Give the pointer back unconditionally.
    ///
    /// Called on shutdown and when the device disappears. Deliberately does not
    /// check `isHiding`: the point is to leave nothing hidden, and releasing
    /// when nothing is held costs nothing.
    func restore() {
        isHiding = false
        visibility.release()
    }
}
