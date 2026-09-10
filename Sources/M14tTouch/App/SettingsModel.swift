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

    private let store: SettingsStore
    private let apply: (AppSettings) -> Void
    private let calibrationStore: CalibrationStore

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
        calibration = calibrationStore.load()
    }

    func update(status: DriverStatus) {
        self.status = status
    }

    func resetCalibration() {
        calibrationStore.reset()
        calibration = nil
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
