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
/// released exactly. The count also dies with the connection, which is what
/// limits the damage if the process is killed outright: no other process can
/// release our hides, so nothing else can.
final class PrivateCursorVisibility: CursorVisibility {

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SetConnectionProperty =
        @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    /// Sanity bound. A gesture asserts roughly a hundred hides a second, and a
    /// human gesture does not last five minutes; a count beyond this means
    /// something is wrong, and refusing to grow it keeps the release loop finite.
    private static let maximumHides = 30_000

    private let backgroundHidingEnabled: Bool
    private var hideCount = 0

    init() {
        backgroundHidingEnabled = Self.enableBackgroundHiding()
    }

    var isAvailable: Bool { backgroundHidingEnabled }

    func assertHidden() {
        guard backgroundHidingEnabled, hideCount < Self.maximumHides else { return }
        // Errors are deliberately ignored rather than propagated: a failure to
        // hide the pointer must never disturb touch handling (requirement 6).
        CGDisplayHideCursor(CGMainDisplayID())
        hideCount += 1
    }

    func release() {
        guard hideCount > 0 else { return }
        for _ in 0..<hideCount { CGDisplayShowCursor(CGMainDisplayID()) }
        hideCount = 0
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
