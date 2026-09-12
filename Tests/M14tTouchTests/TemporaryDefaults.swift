import Foundation
import XCTest

/// Defaults for tests that never reach the disk.
///
/// The first attempt at fixing the litter kept a real suite and tried to delete
/// its file afterwards. It does not work, and the reason is worth keeping:
/// `cfprefsd` owns the write, not the test process. With the file removed at
/// teardown, empty plists reappeared in `~/Library/Preferences` about a minute
/// after `swift test` had finished — 28 of them in one run. Forcing a flush
/// first brought that down to 7, which is the shape of a race, not of a fix.
///
/// So no file is created at all. `UserDefaults` is documented as subclassable
/// through these three primitives, and everything else — `data(forKey:)`,
/// `string(forKey:)` — is built on them, so a store that reads and writes
/// `Data` is exercised exactly as it would be against the real thing.
final class InMemoryDefaults: UserDefaults {

    private var storage: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? { storage[defaultName] }

    override func set(_ value: Any?, forKey defaultName: String) {
        if let value { storage[defaultName] = value } else { storage[defaultName] = nil }
    }

    override func removeObject(forKey defaultName: String) { storage[defaultName] = nil }
}

/// Finding and removing preference files left by earlier versions of these
/// tests — and by the one test below that still makes a real suite on purpose.
enum TemporaryDefaults {

    /// The prefix every suite these tests make is named with, and the pattern
    /// the sweeper matches. One constant, so a rename cannot leave the sweeper
    /// looking for files nothing creates any more.
    static let prefix = "m14t-tests-"

    static var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences")
    }

    static func fileURL(for suiteName: String) -> URL {
        directory.appendingPathComponent("\(suiteName).plist")
    }

    static func makeSuiteName() -> String { "\(prefix)\(UUID().uuidString)" }

    /// Empty the domain, flush it, detach it, delete the file. All four, in that
    /// order — and still not a guarantee, which is why nothing routine uses it.
    static func remove(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defaults?.synchronize()
        CFPreferencesAppSynchronize(suiteName as CFString)
        UserDefaults.standard.removeSuite(named: suiteName)
        try? FileManager.default.removeItem(at: fileURL(for: suiteName))
    }

    /// Whether a file in the preferences directory is one of ours to delete.
    ///
    /// A separate, pure decision so it can be tested against the names of files
    /// that must never be touched. Everything in that directory belongs to some
    /// other application, and a sweeper with a loose predicate is worse than the
    /// litter it clears.
    static func isOurLeftover(fileName: String) -> Bool {
        fileName.hasPrefix(prefix) && fileName.hasSuffix(".plist")
    }

    /// Clear anything an earlier run left behind. Runs once per test bundle.
    @discardableResult
    static func sweepLeftovers() -> Int {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where isOurLeftover(fileName: name) {
            remove(suiteName: String(name.dropLast(".plist".count)))
            if !manager.fileExists(atPath: directory.appendingPathComponent(name).path) {
                removed += 1
            }
        }
        return removed
    }

    private static var hasSwept = false

    static func sweepOnce() {
        guard !hasSwept else { return }
        hasSwept = true
        sweepLeftovers()
    }
}

/// A test case with defaults of its own that cost nothing to clean up.
class TemporaryDefaultsTestCase: XCTestCase {

    private(set) var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        TemporaryDefaults.sweepOnce()
        defaults = InMemoryDefaults()
    }

    override func tearDownWithError() throws {
        defaults = nil
        try super.tearDownWithError()
    }
}
