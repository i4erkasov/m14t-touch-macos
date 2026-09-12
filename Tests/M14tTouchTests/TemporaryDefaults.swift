import Foundation
import XCTest

/// A `UserDefaults` suite that leaves nothing behind.
///
/// Tests need a real suite rather than a dictionary, because what is being
/// tested is what survives a round trip through the actual preferences system.
/// The cost of that had been 650 empty plists in the runner's
/// `~/Library/Preferences`: `removePersistentDomain` empties a domain but does
/// not remove the file it was stored in, so every run of every test left one
/// more 42-byte husk behind.
///
/// So cleaning up means three things, in order, and the last one is the one
/// that was missing.
enum TemporaryDefaults {

    /// The prefix every suite this makes is named with — and the pattern the
    /// sweeper matches. One constant, so a rename cannot leave the sweeper
    /// looking for files nothing creates any more.
    static let prefix = "m14t-tests-"

    static var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences")
    }

    static func fileURL(for suiteName: String) -> URL {
        directory.appendingPathComponent("\(suiteName).plist")
    }

    /// A suite name nothing else is using.
    static func makeSuiteName() -> String { "\(prefix)\(UUID().uuidString)" }

    /// Empty the domain, detach the suite, and delete the file.
    ///
    /// Idempotent, and safe to call for a suite that was never written to.
    static func remove(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)
        // cfprefsd may have the file open; removing it while empty is still the
        // only thing that makes the directory the same afterwards as before.
        try? FileManager.default.removeItem(at: fileURL(for: suiteName))
    }

    /// Delete any suite left by an earlier run that could not clean up after
    /// itself — a crashed process, or a test killed mid-run. Only files matching
    /// this project's own prefix are touched.
    ///
    /// Whether a file in the preferences directory is one of ours to delete.
    ///
    /// A separate, pure decision so it can be tested against the names of files
    /// that must never be touched. Everything in that directory belongs to some
    /// other application, and a sweeper with a loose predicate is worse than
    /// the litter it clears.
    static func isOurLeftover(fileName: String) -> Bool {
        fileName.hasPrefix(prefix) && fileName.hasSuffix(".plist")
    }

    /// - Returns: how many were removed.
    @discardableResult
    static func sweepLeftovers() -> Int {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where isOurLeftover(fileName: name) {
            let suiteName = String(name.dropLast(".plist".count))
            remove(suiteName: suiteName)
            if !manager.fileExists(atPath: directory.appendingPathComponent(name).path) {
                removed += 1
            }
        }
        return removed
    }
}

/// A test case that gets a throwaway suite and is guaranteed to give it back.
///
/// `tearDown` runs after a failing test as well as a passing one, which is the
/// case that matters: the litter accumulated while the suite was green, but it
/// would have accumulated faster while it was not.
class TemporaryDefaultsTestCase: XCTestCase {

    private(set) var suiteName: String!
    private(set) var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = TemporaryDefaults.makeSuiteName()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        // Registered as well as done in tearDown, so that a failure thrown by a
        // subclass's own setUp — after this one has already made a suite — does
        // not skip the cleanup.
        let name = suiteName!
        addTeardownBlock { TemporaryDefaults.remove(suiteName: name) }
    }

    override func tearDownWithError() throws {
        if let suiteName { TemporaryDefaults.remove(suiteName: suiteName) }
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }
}
