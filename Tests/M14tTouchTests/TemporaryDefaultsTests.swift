import XCTest
@testable import M14tTouch

/// Guards the fix for a bug that left 650 files in the runner's
/// `~/Library/Preferences` — one per test run, for weeks, unnoticed because
/// nothing failed.
final class TemporaryDefaultsTests: TemporaryDefaultsTestCase {

    func testTheSuiteIsRealEnoughToWriteTo() {
        defaults.set("written", forKey: "probe")
        XCTAssertEqual(defaults.string(forKey: "probe"), "written")
    }

    /// The actual regression: the domain was emptied, the file was not removed.
    func testRemovingASuiteRemovesItsFileToo() throws {
        let name = TemporaryDefaults.makeSuiteName()
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.set("something", forKey: "probe")
        suite.synchronize()

        let path = TemporaryDefaults.fileURL(for: name).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                      "the suite did not reach disk, so this test is not testing anything")

        TemporaryDefaults.remove(suiteName: name)

        XCTAssertFalse(FileManager.default.fileExists(atPath: path),
                       "removePersistentDomain empties the domain but leaves the file")
    }

    func testRemovingASuiteThatWasNeverWrittenIsHarmless() {
        let name = TemporaryDefaults.makeSuiteName()
        TemporaryDefaults.remove(suiteName: name)
        TemporaryDefaults.remove(suiteName: name)
    }

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

    /// Tests must never be pointed at the domain the app really uses.
    func testTestsNeverUseTheProductionDomain() {
        XCTAssertTrue(suiteName.hasPrefix(TemporaryDefaults.prefix))
        XCTAssertNotEqual(suiteName, ArgumentParser.appBundleIdentifier)
        XCTAssertNotEqual(suiteName, "m14ttouch")
    }
}
