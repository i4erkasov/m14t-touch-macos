import Foundation
import ServiceManagement

/// Opening the app at login (spec §20).
///
/// `SMAppService` rather than a LaunchAgent plist: it is the supported path on
/// macOS 13 and later, it puts the app in Login Items where a user can find and
/// revoke it, and it needs no file written into their home directory.
enum LoginItem {

    /// Where the last successful registration was made from.
    ///
    /// Kept beside the settings rather than inside them: `AppSettings` is one
    /// JSON blob that round-trips through the UI, and this is bookkeeping about
    /// the installation, not a preference anyone chose.
    private static let recordedPathKey = "loginItemBundlePath"

    private static var defaults: UserDefaults { SettingsStore.shared.defaults }

    /// Whether this build can be a login item at all.
    ///
    /// Only a bundled app can. Registering the command-line binary would ask
    /// macOS to launch a path that moves with every rebuild, so the toggle is
    /// absent there rather than present and broken.
    static var isAvailable: Bool { ArgumentParser.isBundled }

    /// The bundle running now, with symlinks resolved so that two spellings of
    /// the same place do not read as a move.
    static var currentBundlePath: String {
        Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static var recordedBundlePath: String? {
        defaults.string(forKey: recordedPathKey)
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Whether the login item points at a copy of the app that is not this one.
    ///
    /// True after the app is moved — installed to `/Applications` by Homebrew
    /// when it used to live in `~/Applications`, say — because macOS keeps the
    /// registration and follows the bundle, even into the Trash.
    static var isStale: Bool {
        guard isAvailable, isEnabled else { return false }
        return recordedBundlePath != currentBundlePath
    }

    /// Whether the user has to approve it in System Settings.
    ///
    /// macOS may hold a registration pending; saying so beats a toggle that
    /// silently springs back.
    static var needsApproval: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .requiresApproval
    }

    /// - Returns: `false` when the change was refused, so the interface can put
    ///   the toggle back rather than showing a state that is not true.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                defaults.set(currentBundlePath, forKey: recordedPathKey)
            } else {
                try SMAppService.mainApp.unregister()
                defaults.removeObject(forKey: recordedPathKey)
            }
            return true
        } catch {
            Log.line("⚠️  Login item \(enabled ? "registration" : "removal") refused: \(error.localizedDescription)")
            return false
        }
    }

    /// Put the registration back on this bundle, if it has drifted off it.
    ///
    /// Called at launch. The case it exists for is an app that moved: macOS
    /// keeps the login item enabled and repoints it at wherever the bundle went,
    /// so a user who installs with Homebrew after having copied the app to
    /// `~/Applications` ends up with a login item aimed at a bundle in the
    /// Trash — enabled, useless, and with nothing in the interface saying so.
    /// Registering again from here replaces the record rather than adding to it:
    /// the system keys it on the bundle identifier, so there is one entry.
    @discardableResult
    static func reconcile() -> LoginItemAction {
        guard isAvailable else { return .doNothing }

        let status = LoginItemStatus(SMAppService.mainApp.status)
        Log.line("🔁 Login item: \(status), recorded \(recordedBundlePath ?? "nothing")")
        let action = LoginItemRegistration.action(
            status: status, recorded: recordedBundlePath, current: currentBundlePath
        )

        switch action {
        case .doNothing:
            break

        case .repoint(let from):
            Log.line("🔁 Login item points at \(from ?? "an unrecorded copy"), "
                       + "this bundle is \(currentBundlePath) — registering again.")
            if setEnabled(true) {
                Log.line("🔁 Login item now opens this copy.")
            }

        case .forgetRecord:
            Log.line("🔁 Login item is no longer registered; forgetting the recorded path.")
            defaults.removeObject(forKey: recordedPathKey)
        }

        return action
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private extension LoginItemStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled:          self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound:         self = .notFound
        case .notRegistered:    self = .notRegistered
        @unknown default:       self = .notFound
        }
    }
}
