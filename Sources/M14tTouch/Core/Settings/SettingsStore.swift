import Foundation

/// Reads and writes `AppSettings`.
///
/// Backed by `UserDefaults` (spec §21) rather than a file, because these are
/// preferences a GUI edits, and because it removes any question of where to put
/// the file and what to do when two processes write it.
///
/// The defaults object is a property rather than `.standard` so tests can use a
/// throwaway suite instead of the real preferences of whoever runs them.
struct SettingsStore {

    private static let key = "settings"

    let defaults: UserDefaults

    /// The store both shapes of the binary use.
    ///
    /// Pinned to an explicit suite rather than `.standard`, because that would
    /// not be the same place twice: an unbundled binary keys its preferences on
    /// the process name and a bundled one on the bundle identifier, so a setting
    /// chosen in the menu bar would vanish when the same build ran from a
    /// terminal, and the other way round. Observed, not hypothesised — the CLI
    /// wrote to a domain called `m14ttouch` while the app would have read
    /// `com.m14ttouch.app`.
    static let shared = SettingsStore(
        defaults: UserDefaults(suiteName: ArgumentParser.appBundleIdentifier) ?? .standard
    )

    /// Saved settings, or `nil` if none exist or the stored value is unreadable.
    ///
    /// Unreadable means unreadable as a whole; individual fields already fall
    /// back to their defaults, so this only fires if the value is not JSON at
    /// all — a hand-edited preference, or a format from far in the future.
    func load() -> AppSettings? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    /// Saved settings, falling back to the defaults. What callers usually want.
    func loadOrDefault() -> AppSettings { load() ?? AppSettings() }

    /// Persist. Failures are silent by design: a missed save means the user
    /// adjusts a setting again, never a crash.
    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
