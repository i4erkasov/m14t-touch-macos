import Foundation

/// What the system says about a login-item registration.
///
/// A mirror of `SMAppService.Status` with no ServiceManagement in it, so the
/// decision below can be tested without a bundle, a login session or a system
/// database to put one in.
enum LoginItemStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// What to do about it.
enum LoginItemAction: Equatable {
    /// The registration is right, or is the user's to settle in System Settings.
    case doNothing
    /// Register again from this bundle, replacing whatever the record points at.
    case repoint(from: String?)
    /// The system has no registration; stop claiming we made one.
    case forgetRecord
}

/// Deciding what a login item needs, given where it says it points.
///
/// The problem this exists for: macOS follows the app bundle when it moves and
/// keeps the registration enabled — measured, with the bundle in the Trash and
/// the BTM record happily pointing at `file:///Users/…/.Trash/M14t%20Touch.app/`.
/// `SMAppService` offers no way to read the registered path back, so the app
/// remembers where it last registered from and compares that with where it is
/// running from now.
enum LoginItemRegistration {

    /// - Parameters:
    ///   - recorded: the bundle path the last successful registration was made
    ///     from, or nil if this app has never recorded one.
    ///   - current: the bundle path running now.
    static func action(status: LoginItemStatus,
                       recorded: String?,
                       current: String) -> LoginItemAction {
        switch status {
        case .enabled:
            // nil means an older build registered it, or another copy did.
            // Either way the record cannot vouch for where it points, and
            // registering again from here is both harmless and the fix.
            return recorded == current ? .doNothing : .repoint(from: recorded)

        case .requiresApproval:
            // The user has to allow it in System Settings. Registering again
            // would not help and might reset that decision.
            return .doNothing

        case .notRegistered, .notFound:
            // Never re-enable something the user turned off — only stop
            // remembering a registration that no longer exists.
            return recorded == nil ? .doNothing : .forgetRecord
        }
    }
}
