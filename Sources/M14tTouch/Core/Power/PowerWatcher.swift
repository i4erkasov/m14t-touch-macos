import AppKit
import Foundation

/// Tells the driver when the machine is about to sleep and when it has woken.
///
/// Why this matters here more than in most applications: the panel is held
/// **exclusively**. Sleeping while holding a device, and then finding it again
/// on the other side, is exactly the situation in which an exclusive claim goes
/// stale — the collection stops reporting while the driver still believes it
/// owns it. That failure has been seen on this hardware
/// (`docs/M14t_PEN_CAPABILITIES.md`), and unplugging the cable was the only cure.
/// Releasing before sleep and taking the panel again afterwards removes the
/// occasion for it.
///
/// `NSWorkspace`'s notifications rather than `IOPMConnection`: they are public,
/// they are delivered on the main queue, and the process already links AppKit.
final class PowerWatcher {

    private var observers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - willSleep: run before the machine sleeps. The system waits for this,
    ///     but not for long — releasing a device is within its patience,
    ///     anything slower is not.
    ///   - didWake: run once the machine is awake again.
    init(willSleep: @escaping () -> Void, didWake: @escaping () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { _ in willSleep() },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { _ in didWake() }
        ]
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }
}
