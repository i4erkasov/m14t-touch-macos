import XCTest
@testable import M14tTouch

/// The rule that decides whether a login item needs repointing.
///
/// Written against a real failure: after `brew install --cask`, the app lived in
/// `/Applications` while its login item still pointed at the copy in
/// `~/Applications` — which, once that copy was thrown away, meant the system
/// was cheerfully registered to open something in the Trash.
final class LoginItemRegistrationTests: XCTestCase {

    private let here = "/Applications/M14t Touch.app"
    private let there = "/Users/someone/Applications/M14t Touch.app"
    private let trash = "/Users/someone/.Trash/M14t Touch.app"

    func testAnEnabledItemRegisteredFromThisBundleIsLeftAlone() {
        XCTAssertEqual(
            LoginItemRegistration.action(status: .enabled, recorded: here, current: here),
            .doNothing)
    }

    func testAnEnabledItemRegisteredFromElsewhereIsRepointed() {
        XCTAssertEqual(
            LoginItemRegistration.action(status: .enabled, recorded: there, current: here),
            .repoint(from: there))
    }

    func testAnItemPointingIntoTheTrashIsRepointed() {
        XCTAssertEqual(
            LoginItemRegistration.action(status: .enabled, recorded: trash, current: here),
            .repoint(from: trash))
    }

    /// An app that was made a login item before this bookkeeping existed has no
    /// record. It cannot be assumed correct, and registering again is harmless.
    func testAnEnabledItemWithNoRecordIsRepointed() {
        XCTAssertEqual(
            LoginItemRegistration.action(status: .enabled, recorded: nil, current: here),
            .repoint(from: nil))
    }

    /// Registering again while macOS is waiting for the user to allow it would
    /// not help, and might reset the decision they are in the middle of making.
    func testAPendingApprovalIsNotTouched() {
        XCTAssertEqual(
            LoginItemRegistration.action(status: .requiresApproval, recorded: nil, current: here),
            .doNothing)
        XCTAssertEqual(
            LoginItemRegistration.action(status: .requiresApproval, recorded: there, current: here),
            .doNothing)
    }

    /// The one thing this must never do: switch the setting back on for someone
    /// who turned it off.
    func testAnItemTheUserTurnedOffIsNotReRegistered() {
        for status in [LoginItemStatus.notRegistered, .notFound] {
            XCTAssertEqual(
                LoginItemRegistration.action(status: status, recorded: here, current: here),
                .forgetRecord,
                "\(status) must only clear the record")
            XCTAssertEqual(
                LoginItemRegistration.action(status: status, recorded: nil, current: here),
                .doNothing,
                "\(status) with nothing recorded has nothing to do")
        }
    }

    /// Repointing must be a replacement, never an addition. The system keys the
    /// registration on the bundle identifier, so there is one entry to replace —
    /// and the decision below only ever asks for one registration.
    func testRepointingAsksForOneRegistrationNotTwo() {
        let action = LoginItemRegistration.action(status: .enabled, recorded: there, current: here)
        guard case .repoint = action else { return XCTFail("expected a repoint") }
        XCTAssertNotEqual(action, .forgetRecord)
    }
}
