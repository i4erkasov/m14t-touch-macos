import Foundation

/// A colour in a form that can be saved.
///
/// Neither SwiftUI's `Color` nor AppKit's `NSColor` is `Codable`, and archiving
/// an `NSColor` would tie a preferences file to a class name. Four numbers in
/// sRGB are the smallest thing that survives a version, and sRGB specifically so
/// the colour means the same on any display.
struct RGBAColor: Equatable, Codable {

    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// macOS's own green, read from `NSColor.systemGreen` in sRGB rather than
    /// guessed, so the default looks like part of the system.
    static let systemGreen = RGBAColor(red: 0.1882, green: 0.8196, blue: 0.3451)

    /// Decoded component by component, each falling back, for the same reason
    /// the settings around it are: a file written by another version must not
    /// become undecodable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = RGBAColor.systemGreen
        func value(_ key: CodingKeys, _ fallback: Double) -> Double {
            (try? container.decodeIfPresent(Double.self, forKey: key)) as? Double ?? fallback
        }
        red = value(.red, fallback.red)
        green = value(.green, fallback.green)
        blue = value(.blue, fallback.blue)
        alpha = value(.alpha, fallback.alpha)
    }
}
