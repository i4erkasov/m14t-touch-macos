import Foundation
import ServiceManagement

/// Opening the app at login (spec §20).
///
/// `SMAppService` rather than a LaunchAgent plist: it is the supported path on
/// macOS 13 and later, it puts the app in Login Items where a user can find and
/// revoke it, and it needs no file written into their home directory.
enum LoginItem {

    /// Whether this build can be a login item at all.
    ///
    /// Only a bundled app can. Registering the command-line binary would ask
    /// macOS to launch a path that moves with every rebuild, so the toggle is
    /// absent there rather than present and broken.
    static var isAvailable: Bool { ArgumentParser.isBundled }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
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
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
