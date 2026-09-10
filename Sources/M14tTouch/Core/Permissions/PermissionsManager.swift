import AppKit
import ApplicationServices
import IOKit.hid

/// The two permissions the driver cannot work without (spec §19).
///
/// Both are granted per binary, keyed on its code signature and path, which is
/// why the app needs its own grants even on a machine where the command-line
/// build already has them — and why an ad-hoc signature that changes with every
/// build can make a rebuilt app look like a stranger to the permission system.
enum Permission: CaseIterable {

    /// Reading the raw HID touch stream.
    case inputMonitoring

    /// Posting cursor, click and scroll events.
    case accessibility

    var title: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility:   return "Accessibility"
        }
    }

    var explanation: String {
        switch self {
        case .inputMonitoring: return "Reads touches from the panel."
        case .accessibility:   return "Moves the pointer and clicks."
        }
    }

    /// The System Settings pane that grants it.
    var settingsURL: URL? {
        switch self {
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}

/// Reads permission status without asking for it.
///
/// Checking and prompting are separate on purpose: the interface wants to *show*
/// what is missing whenever it is looked at, and a check that prompted would
/// throw a dialogue in the user's face every time the window opened.
enum PermissionsManager {

    static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted()
        case .inputMonitoring:
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
    }

    static var allGranted: Bool { Permission.allCases.allSatisfy(isGranted) }

    /// Ask the system to prompt, where it can.
    ///
    /// macOS only shows each prompt once per application, and never again after
    /// a refusal, so `openSettings` is the reliable path and this is the polite
    /// first try.
    static func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(
                ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            )
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    static func openSettings(for permission: Permission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
