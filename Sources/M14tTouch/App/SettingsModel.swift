import AppKit
import Combine
import Foundation

/// What the settings window edits.
///
/// Every change is applied immediately and saved immediately — there is no OK
/// button. Touch settings are judged by using them, and a dialogue that made you
/// commit before finding out whether the sensitivity felt right would be the
/// wrong shape for this.
@MainActor
final class SettingsModel: ObservableObject {

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            apply(settings)
        }
    }

    /// Whether the panel is connected, mirrored from the driver.
    @Published private(set) var status: DriverStatus

    /// The displays available to choose between, re-read whenever the window
    /// opens: monitors come and go while the app is running.
    @Published private(set) var displays: [DisplayInfo] = []

    /// The calibration in force, shown read-only until v0.4 gives it a UI.
    @Published private(set) var calibration: CalibrationData?

    /// Which permissions are missing, re-read rather than remembered: the user
    /// grants them in another application, so nothing tells us when it changes.
    @Published private(set) var permissions: [Permission: Bool] = [:]

    private let store: SettingsStore
    private let apply: (AppSettings) -> Void
    private let calibrationStore: CalibrationStore

    /// Starts guided calibration, or `nil` when there is no app to host it —
    /// the command-line build has no overlay to show.
    var startCalibration: (() -> Void)?

    init(
        settings: AppSettings,
        status: DriverStatus,
        store: SettingsStore = .shared,
        calibrationStore: CalibrationStore = .shared,
        apply: @escaping (AppSettings) -> Void
    ) {
        self.settings = settings
        self.status = status
        self.store = store
        self.calibrationStore = calibrationStore
        self.apply = apply
        refresh()
    }

    /// Re-read what the world looks like right now.
    func refresh() {
        displays = DisplayResolver.all()
        calibration = calibrationStore.load(for: selectedDisplayIdentity)
        permissions = Dictionary(
            uniqueKeysWithValues: Permission.allCases.map { ($0, PermissionsManager.isGranted($0)) }
        )
    }

    /// The displays worth offering as a touch target.
    ///
    /// External ones only. A touch panel is by definition not the built-in
    /// screen, and mapping touches onto a screen nobody can reach is not a
    /// choice anyone means to make.
    ///
    /// It stops there. Which external display carries the touch panel cannot be
    /// known: the touch interface identifies itself as `2D1F:524C` over USB and
    /// the monitor as vendor `30AE` over EDID, and nothing connects the two. So
    /// a second external monitor is listed alongside, and the user says which.
    var selectableDisplays: [DisplayInfo] {
        let external = displays.filter { !$0.isBuiltin }
        return external.isEmpty ? displays : external
    }

    /// What macOS calls the target display, for showing to a person.
    var displayName: String {
        DisplayResolver.resolve(settings.display, among: displays)?.display.name ?? "Touch display"
    }

    func isGranted(_ permission: Permission) -> Bool { permissions[permission] ?? false }

    func grant(_ permission: Permission) {
        // Ask first, then show the pane: the prompt appears at most once per
        // application and never after a refusal, so it cannot be relied on
        // alone, but it is the shorter path when it does appear.
        PermissionsManager.request(permission)
        PermissionsManager.openSettings(for: permission)
    }

    func update(status: DriverStatus) {
        self.status = status
    }

    /// Put the diagnostics on the pasteboard, for pasting into a bug report.
    ///
    /// Plain text rather than a file: the point is to be able to paste it
    /// somewhere, and a file would need saving, finding and attaching.
    func copyDiagnostics() {
        var lines = [
            "M14t Touch diagnostics",
            "",
            "Display:     \(displayName)",
            "Interface:   \(status.deviceName ?? "not connected")",
            "Identifiers: \(status.identifiers ?? "—")",
            "Mode:        \(settings.mode.rawValue)",
            "Pen:         \(settings.penEnabled ? "handled" : "left to macOS")",
        ]
        if let calibration {
            lines.append("Calibration: X \(Int(calibration.xMin))–\(Int(calibration.xMax))"
                         + "  Y \(Int(calibration.yMin))–\(Int(calibration.yMax))")
        } else {
            lines.append("Calibration: none saved")
        }
        lines.append("")
        lines.append("Displays:")
        for display in displays {
            lines.append("  \(Int(display.bounds.width)) × \(Int(display.bounds.height))"
                         + " at \(Int(display.bounds.minX)), \(Int(display.bounds.minY))"
                         + (display.isBuiltin ? "  (built-in)" : ""))
        }
        lines.append("")
        lines.append("Permissions:")
        for permission in Permission.allCases {
            lines.append("  \(permission.title): \(isGranted(permission) ? "granted" : "missing")")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func resetCalibration() {
        calibrationStore.reset(for: selectedDisplayIdentity)
        calibration = nil
    }

    /// The identity of the display currently selected, if it has one.
    ///
    /// Calibration is shown and reset for the display the panel is mapped to,
    /// not globally: with entries kept per display, a reset that wiped every one
    /// of them would be a surprise.
    private var selectedDisplayIdentity: DisplayIdentity? {
        DisplayResolver.resolve(settings.display, among: displays)?.display.identity
    }

    /// Choose a display, remembering it by identity where it has one so it is
    /// found again after replugging (spec §17).
    func selectDisplay(_ display: DisplayInfo) {
        settings.display = DisplaySelection(
            identity: display.identity.isUsable ? display.identity : nil,
            index: display.index
        )
    }

    /// Which of the listed displays the current selection points at.
    var selectedDisplayIndex: Int? {
        DisplayResolver.resolve(settings.display, among: displays)?.display.index
    }
}
