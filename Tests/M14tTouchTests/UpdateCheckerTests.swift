import XCTest
@testable import M14tTouch

/// Comparing one version against another, and deciding what to say about it.
///
/// The network half cannot be tested and is injected away; what is left is the
/// part that can be wrong quietly — telling someone to install a version older
/// than the one they are running, or never telling them at all.
final class UpdateCheckerTests: XCTestCase {

    // MARK: - Reading a version

    func testALeadingVeeIsOptional() {
        XCTAssertEqual(Version("v1.2.3"), Version("1.2.3"))
    }

    // The case text comparison gets wrong, and the reason this is parsed.
    func testTenComesAfterNine() {
        XCTAssertTrue(Version("v1.0.9")! < Version("v1.0.10")!)
    }

    func testMissingFieldsAreZero() {
        XCTAssertEqual(Version("1.0"), Version("1.0.0"))
        XCTAssertTrue(Version("1.0")! < Version("1.0.1")!)
    }

    func testSomethingThatIsNotAVersionIsRefused() {
        XCTAssertNil(Version("nightly"))
        XCTAssertNil(Version(""))
        XCTAssertNil(Version("v"))
        XCTAssertNil(Version("v1.x.3"))
    }

    // `git describe` names a development build after the tag it grew from.
    func testADevelopmentBuildIsAheadOfTheTagItCameFrom() {
        let released = Version("v1.0.1")!
        let built = Version("v1.0.1-3-ge788140")!
        XCTAssertTrue(built > released)
    }

    func testADirtyBuildIsStillReadable() {
        XCTAssertNotNil(Version("v1.0.1-3-ge788140-dirty"))
    }

    // MARK: - Deciding what to say

    private func checker(latest tag: String) -> UpdateChecker {
        var checker = UpdateChecker()
        checker.fetch = { (tag, "https://example.invalid/\(tag)") }
        return checker
    }

    func testANewerReleaseIsOffered() async {
        let outcome = await checker(latest: "v1.1.0").check(current: "v1.0.1")
        guard case .updateAvailable(let latest, _) = outcome else {
            return XCTFail("expected an update: \(outcome)")
        }
        XCTAssertEqual(latest, "v1.1.0")
    }

    func testTheSameVersionIsUpToDate() async {
        let outcome = await checker(latest: "v1.0.1").check(current: "v1.0.1")
        XCTAssertEqual(outcome, .upToDate(current: "v1.0.1"))
    }

    // An older release must never be offered as an update. This is the failure
    // that would send someone backwards without either of us noticing.
    func testAnOlderReleaseIsNotOffered() async {
        let outcome = await checker(latest: "v1.0.0").check(current: "v1.0.1")
        XCTAssertEqual(outcome, .upToDate(current: "v1.0.1"))
    }

    // And a build made after the release it grew from is not told to install
    // the release it grew from.
    func testADevelopmentBuildIsNotToldToDowngrade() async {
        let outcome = await checker(latest: "v1.0.1").check(current: "v1.0.1-3-ge788140")
        XCTAssertEqual(outcome, .upToDate(current: "v1.0.1-3-ge788140"))
    }

    func testAFailedRequestSaysSoRatherThanClaimingToBeUpToDate() async {
        var checker = UpdateChecker()
        checker.fetch = { throw URLError(.notConnectedToInternet) }
        guard case .unknown = await checker.check(current: "v1.0.1") else {
            return XCTFail("a failure must not read as good news")
        }
    }

    // The command-line build has no bundle and therefore no version.
    func testABuildWithoutAVersionSaysSo() async {
        guard case .unknown = await checker(latest: "v1.0.1").check(current: nil) else {
            return XCTFail("expected unknown")
        }
    }

    func testAnUnparseableReleaseTagIsNotAnUpdate() async {
        guard case .unknown = await checker(latest: "nightly").check(current: "v1.0.1") else {
            return XCTFail("expected unknown")
        }
    }
}
