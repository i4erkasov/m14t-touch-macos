import XCTest
@testable import M14tTouch

/// Guards the fix for a bug that left 657 files in the runner's
/// `~/Library/Preferences` — a few per test run, for days, unnoticed because
/// nothing ever failed.
final class TemporaryDefaultsTests: TemporaryDefaultsTestCase {

    // MARK: - The defaults tests actually use

    func testTheDefaultsAreRealEnoughToStoreValues() {
        defaults.set("written", forKey: "probe")
        XCTAssertEqual(defaults.string(forKey: "probe"), "written")
        defaults.removeObject(forKey: "probe")
        XCTAssertNil(defaults.object(forKey: "probe"))
    }

    /// `SettingsStore` reads and writes `Data`, which `UserDefaults` builds on
    /// the three primitives the in-memory subclass overrides. If that stopped
    /// being true, every settings test would be testing nothing.
    func testDataRoundTripsThroughTheInMemoryDefaults() throws {
        let payload = try XCTUnwrap("{\"mode\":\"touchscreen\"}".data(using: .utf8))
        defaults.set(payload, forKey: "settings")
        XCTAssertEqual(defaults.data(forKey: "settings"), payload)
    }

    /// The actual regression, stated as a property of the whole suite: running
    /// these tests must not create a preferences file.
    func testNoTestWritesAPreferencesFile() throws {
        let manager = FileManager.default
        let names = try manager.contentsOfDirectory(atPath: TemporaryDefaults.directory.path)
        let ours = names.filter { TemporaryDefaults.isOurLeftover(fileName: $0) }
        XCTAssertEqual(ours, [], "these tests are writing preference files again: \(ours)")
    }

    func testTheDefaultsAreNotTheProcessWideOnes() {
        XCTAssertFalse(defaults === UserDefaults.standard)
        defaults.set("only here", forKey: "m14t-probe-that-must-not-escape")
        XCTAssertNil(UserDefaults.standard.object(forKey: "m14t-probe-that-must-not-escape"))
    }

    // MARK: - The sweeper

    /// The sweeper runs against a directory full of other applications'
    /// preferences. What it will not touch matters more than what it will.
    func testTheSweeperMatchesOnlyThisProjectsOwnTestFiles() {
        XCTAssertTrue(TemporaryDefaults.isOurLeftover(
            fileName: "m14t-tests-0032CC98-534F-4B28-A64D-34DFC95D6A87.plist"))

        for other in ["com.apple.finder.plist",
                      "com.m14ttouch.app.plist",     // the real settings
                      "m14ttouch.plist",             // the CLI's own domain
                      ".GlobalPreferences.plist",
                      "m14t-tests-something.txt",    // right prefix, not a plist
                      "prefix-m14t-tests-x.plist"] { // prefix not at the start
            XCTAssertFalse(TemporaryDefaults.isOurLeftover(fileName: other),
                           "\(other) is not ours to delete")
        }
    }

    func testSuiteNamesCarryThePrefixTheSweeperLooksFor() {
        let name = TemporaryDefaults.makeSuiteName()
        XCTAssertTrue(TemporaryDefaults.isOurLeftover(fileName: "\(name).plist"))
        XCTAssertNotEqual(name, ArgumentParser.appBundleIdentifier)
        XCTAssertNotEqual(name, "m14ttouch")
    }

    /// That a real suite can be removed file and all — on request only.
    ///
    /// Not run by default, and the reason is the bug itself: `cfprefsd` writes
    /// the file out after this process exits, so merely creating one real suite
    /// leaves behind the litter this whole change is about. Run it deliberately:
    ///
    ///     M14T_TEST_REAL_DEFAULTS=1 swift test --filter RealSuite
    func testRemovingARealSuiteRemovesItsFileToo() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["M14T_TEST_REAL_DEFAULTS"] == "1",
                          "creates a real preferences file; see the comment above")

        let name = TemporaryDefaults.makeSuiteName()
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.set("something", forKey: "probe")
        suite.synchronize()

        let path = TemporaryDefaults.fileURL(for: name).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        TemporaryDefaults.remove(suiteName: name)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}
