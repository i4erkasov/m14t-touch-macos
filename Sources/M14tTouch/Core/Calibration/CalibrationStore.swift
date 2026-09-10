import Foundation

/// Reads and writes calibration, one entry per display (spec §15).
///
/// A single stored value was wrong the moment a second panel appeared, and lost
/// a calibration whenever a display was swapped. Entries are keyed on the
/// display identity introduced in v0.3, so a panel is recognised again after
/// replugging.
///
/// The location is a property rather than a hardcoded constant so tests can
/// point it at a temporary directory. They otherwise would have to read and
/// write the real `~/.m14ttouch.json` — which would destroy the calibration of
/// whoever ran them.
struct CalibrationStore {

    /// Location of the persisted calibration file.
    let url: URL

    /// The store the driver uses: `~/.m14ttouch.json`.
    static let shared = CalibrationStore(
        url: FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".m14ttouch.json")
    )

    /// The file's shape.
    private struct Stored: Codable {
        var displays: [String: CalibrationData] = [:]

        /// A calibration written before storage was per display.
        ///
        /// Kept as a fallback for displays that have none of their own, rather
        /// than discarded on upgrade: people have calibrated already, and
        /// throwing it away is a regression they would feel immediately.
        var shared: CalibrationData?
    }

    // MARK: - Reading

    /// The calibration for a display: its own if it has one, otherwise whatever
    /// was saved before calibration was per display.
    func load(for identity: DisplayIdentity?) -> CalibrationData? {
        let stored = read()
        return stored.displays[key(for: identity)] ?? stored.shared
    }

    /// Where a display's entry lives.
    ///
    /// A missing identity is not a special case but the same case as a display
    /// that reports none: both land in the unidentified bucket. Treating them
    /// differently meant a value saved with no identity could not be read back
    /// with none either.
    private func key(for identity: DisplayIdentity?) -> String {
        (identity ?? DisplayIdentity(vendor: 0, model: 0, serial: 0)).storageKey
    }

    // MARK: - Writing

    /// Persist for one display. Failures are silent by design — a missed save
    /// means recalibrating next launch, never a crash.
    func save(_ calibration: CalibrationData, for identity: DisplayIdentity?) {
        var stored = read()
        stored.displays[key(for: identity)] = calibration
        write(stored)
    }

    /// Forget one display's calibration, and the pre-v0.4 value with it.
    ///
    /// Both, because leaving the old shared value behind would make a reset look
    /// like it had done nothing: the display would simply fall back to it.
    @discardableResult
    func reset(for identity: DisplayIdentity?) -> Bool {
        var stored = read()
        let entry = key(for: identity)
        let hadSomething = stored.displays[entry] != nil || stored.shared != nil
        stored.displays[entry] = nil
        stored.shared = nil
        write(stored)
        return hadSomething
    }

    /// Delete the file entirely — every display.
    @discardableResult
    func resetAll() -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }

    // MARK: - File

    private func read() -> Stored {
        guard let data = try? Data(contentsOf: url) else { return Stored() }
        if let stored = try? JSONDecoder().decode(Stored.self, from: data) { return stored }
        // A file from before this version holds a bare calibration.
        if let legacy = try? JSONDecoder().decode(CalibrationData.self, from: data) {
            return Stored(shared: legacy)
        }
        return Stored()
    }

    private func write(_ stored: Stored) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(stored) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
