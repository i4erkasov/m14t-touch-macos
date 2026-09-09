import Dispatch
import Foundation

/// Runs a cleanup block when the process is asked to quit.
///
/// The driver holds the left mouse button down for as long as a finger is on
/// the panel. Quitting mid-contact — Ctrl-C during a drag, which is exactly the
/// workflow the README invites — left that button pressed, with no finger to
/// lift it and nothing in the system to release it. Every subsequent hover
/// became a drag until the user clicked somewhere to break it.
///
/// Built on GCD signal sources rather than `signal(2)` handlers: a C handler
/// cannot capture context and may only call async-signal-safe functions, which
/// posting a `CGEvent` decidedly is not. A dispatch source delivers on an
/// ordinary queue, where ordinary code is safe to run.
///
/// `SIGKILL` cannot be caught, so `kill -9` still strands the button. Nothing
/// in user space can change that.
final class ShutdownHandler {

    private let sources: [DispatchSourceSignal]

    /// - Parameter handle: run on the main queue when a quit signal arrives.
    init(signals: [Int32] = [SIGINT, SIGTERM], handle: @escaping () -> Void) {
        sources = signals.map { number in
            // The default disposition terminates the process before GCD ever
            // sees the signal, so it has to be ignored first.
            signal(number, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler(handler: handle)
            source.resume()
            return source
        }
    }
}
