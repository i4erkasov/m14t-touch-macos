import CoreGraphics
import Foundation

/// Hides the pointer from a background process using a private CoreGraphics
/// Services property.
///
/// The one private API this project uses, permitted by the spec amendment
/// solely for cursor visibility, and confined to this file.
///
/// ## What was measured
/// `CGDisplayHideCursor` is ignored from a background process unless the
/// connection has `SetsCursorInBackground` set. With it set, a single hide makes
/// the pointer blink out and return; holding it down needs the request repeated,
/// which is why `assertHidden()` is called every frame rather than once.
///
/// **Any movement of the pointer makes it visible again.** That is a property of
/// the window server, not of this code, and it is why hiding only ever shows up
/// during the stationary part of a scroll — a tap and a drag move the pointer by
/// design.
///
/// ## Safety
/// Hides are reference counted per connection, so every one is counted here and
/// released exactly.
///
/// What happens when the process is killed outright rests on that count dying
/// with the connection. One staged test — 175 unbalanced hides, then SIGKILL —
/// looked like the pointer came back on its own, but the observation was
/// tentative and has not been repeated. Treat it as likely rather than
/// established, and note that no other process can release these hides, so if
/// the window server does not, nothing else will.
final class PrivateCursorVisibility: CursorVisibility {

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SetConnectionProperty =
        @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    /// Sanity bound. A gesture asserts roughly a hundred hides a second, and a
    /// human gesture does not last five minutes; a count beyond this means
    /// something is wrong, and refusing to grow it keeps the release loop finite.
    private static let maximumHides = 30_000

    /// Guards the count and the lazily-resolved availability. The count is
    /// touched from the touch queue on every frame and from the main thread at
    /// shutdown, and losing a decrement there means a pointer that never comes
    /// back.
    private let lock = NSLock()
    private var hideCount = 0
    private var resolved: Bool?

    /// Whether the private path is usable, resolved on first ask and remembered.
    ///
    /// Lazily, so that constructing this costs nothing and touches no private
    /// API until hiding is actually switched on. That is what lets the app hold
    /// one of these from the start regardless of the setting — the alternative,
    /// choosing the implementation at launch from the setting at launch, made
    /// enabling hiding later do nothing at all.
    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let resolved { return resolved }
        let value = Self.enableBackgroundHiding()
        resolved = value
        return value
    }

    func assertHidden() {
        guard isAvailable else { return }
        lock.lock()
        defer { lock.unlock() }
        guard hideCount < Self.maximumHides else { return }
        // Errors are deliberately ignored rather than propagated: a failure to
        // hide the pointer must never disturb touch handling (requirement 6).
        CGDisplayHideCursor(CGMainDisplayID())
        hideCount += 1
    }

    func release() {
        lock.lock()
        let outstanding = hideCount
        hideCount = 0
        lock.unlock()

        guard outstanding > 0 else { return }
        for _ in 0..<outstanding { CGDisplayShowCursor(CGMainDisplayID()) }
    }

    // MARK: - Private API resolution

    /// Resolved at runtime rather than linked, so a symbol that disappears in a
    /// future macOS leaves the driver working with hiding switched off, instead
    /// of failing to launch (requirement 2).
    private static func enableBackgroundHiding() -> Bool {
        guard let framework = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY
        ) else { return false }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let raw = dlsym(framework, name) else { return nil }
            return unsafeBitCast(raw, to: type)
        }

        guard let mainConnectionID = symbol("CGSMainConnectionID", as: MainConnectionID.self),
              let setProperty = symbol("CGSSetConnectionProperty", as: SetConnectionProperty.self)
        else { return false }

        let connection = mainConnectionID()
        guard connection != 0 else { return false }

        return setProperty(
            connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue
        ) == 0
    }
}
