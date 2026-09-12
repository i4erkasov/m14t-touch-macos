import XCTest
@testable import M14tTouch

/// Covers persistence and, more importantly, what happens to a stored value
/// written by an older version. Getting that wrong resets everything the user
/// configured, silently, on upgrade.
final class SettingsTests: TemporaryDefaultsTestCase {

    private var store: SettingsStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = SettingsStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        store = nil
        try super.tearDownWithError()
    }

    private func makeSettings() -> AppSettings {
        var settings = AppSettings()
        settings.mode = .touchscreen
        settings.display = .index(2)
        settings.invertY = true
        settings.gestures.scrollSensitivity = 2.5
        settings.gestures.cursorHiding = .scrolling
        return settings
    }

    // MARK: - Round trip

    func testNothingIsStoredInitially() {
        XCTAssertNil(store.load())
        XCTAssertEqual(store.loadOrDefault(), AppSettings())
    }

    func testSettingsRoundTrip() {
        let settings = makeSettings()
        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testResetForgetsThem() {
        store.save(makeSettings())
        store.reset()
        XCTAssertNil(store.load())
    }

    // MARK: - Forward compatibility

    // The reason decoding is written by hand. A file from a version that did not
    // know about a setting must keep every setting it did know about, not reset
    // them all because one key is missing.
    func testAFileMissingKeysKeepsTheOnesItHas() throws {
        let json = """
        { "mode": "touchscreen", "display": { "index": 3 } }
        """
        defaults.set(Data(json.utf8), forKey: "settings")

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.mode, .touchscreen)
        XCTAssertEqual(loaded.display.index, 3)
        XCTAssertEqual(loaded.invertY, AppSettings().invertY)
        XCTAssertEqual(loaded.gestures, GestureConfiguration())
    }

    func testAPartialGestureBlockKeepsTheRestOfTheDefaults() throws {
        let json = """
        { "gestures": { "longPressDelay": 0.9 } }
        """
        defaults.set(Data(json.utf8), forKey: "settings")

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.gestures.longPressDelay, 0.9)
        XCTAssertEqual(loaded.gestures.scrollThreshold, GestureConfiguration().scrollThreshold)
        XCTAssertEqual(loaded.gestures.cursorHiding, .never)
    }

    // Unreadable as a whole is different from missing a field: fall back rather
    // than crash on a hand-edited preference.
    func testGibberishLoadsAsNothing() {
        defaults.set(Data("not json".utf8), forKey: "settings")
        XCTAssertNil(store.load())
        XCTAssertEqual(store.loadOrDefault(), AppSettings())
    }

    // MARK: - Command line over stored settings

    func testArgumentsOverrideStoredSettings() {
        var stored = AppSettings()
        stored.mode = .mouse
        stored.gestures.scrollSensitivity = 3

        guard case .run(let config) = ArgumentParser.parse(
            ["--mode", "touchscreen"], defaults: stored.touchConfig
        ) else { return XCTFail("expected a run outcome") }

        XCTAssertEqual(config.mode, .touchscreen)          // overridden
        XCTAssertEqual(config.gestures.scrollSensitivity, 3) // untouched, from settings
    }

    func testStoredSettingsSurviveWhenNoArgumentsAreGiven() {
        var stored = AppSettings()
        stored.display = .index(4)
        stored.invertX = true

        guard case .run(let config) = ArgumentParser.parse([], defaults: stored.touchConfig)
        else { return XCTFail("expected a run outcome") }

        XCTAssertEqual(config.display.index, 4)
        XCTAssertTrue(config.invertX)
    }
}
