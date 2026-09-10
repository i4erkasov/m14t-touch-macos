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
