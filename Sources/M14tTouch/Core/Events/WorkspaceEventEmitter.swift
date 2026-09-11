import AppKit
import Foundation

/// Carries out actions that are requests to the system rather than input.
///
/// There is one, and it is here because the obvious route failed. A trackpad's
/// three-finger swipe up runs macOS's Mission Control shortcut, and that
/// shortcut does not answer a synthesised keystroke — neither with the
/// modifier flagged on the event nor with Control genuinely held down, both
/// measured on the hardware. Opening `Mission Control.app` does work, and it is
/// a documented application in a documented place.
struct WorkspaceEventEmitter: EventEmitter {

    /// Where macOS keeps it. A path rather than a bundle identifier because it
    /// is a system application in a fixed location, and a missing one should
    /// fail quietly rather than launch something else that answers to the name.
    static let missionControl = URL(fileURLWithPath: "/System/Applications/Mission Control.app")

    func emit(_ action: InputAction) {
        guard case .showAllWindows = action else { return }
        guard FileManager.default.fileExists(atPath: Self.missionControl.path) else { return }

        NSWorkspace.shared.openApplication(
            at: Self.missionControl,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
