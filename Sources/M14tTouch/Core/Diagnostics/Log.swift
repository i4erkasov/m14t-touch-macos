import Foundation
import os

/// Where the driver's running commentary goes.
///
/// `print` is enough for the CLI, whose output the user is watching, and is
/// nothing at all for the packaged app: a bundle launched from Finder has no
/// stdout anyone can read, so every message written that way was lost exactly
/// when it was most needed. Messages therefore go to the unified log as well,
/// and a problem in the menu-bar app can be read back afterwards with
///
///     log show --last 5m --predicate 'subsystem == "com.m14ttouch.app"' --info
enum Log {

    private static let logger = Logger(
        subsystem: ArgumentParser.appBundleIdentifier, category: "driver"
    )

    /// One line of narration: the same text to stdout and to the system log.
    ///
    /// Marked public in the log because none of it is private — device names,
    /// display sizes and error codes are what someone would need to read back
    /// to us, and a redacted log is a log that cannot be used for support.
    static func line(_ message: String) {
        print(message)
        logger.log("\(message, privacy: .public)")
    }
}
