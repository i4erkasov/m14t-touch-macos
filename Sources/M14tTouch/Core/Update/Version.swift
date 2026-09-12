import Foundation

/// A released version, for comparing one against another.
///
/// Parsed rather than compared as text, because text ordering gets this wrong
/// in the one case that matters: "v1.0.10" sorts before "v1.0.9".
///
/// Development builds are the other thing this has to survive. The bundle's
/// version comes from `git describe`, so a build made after a release looks
/// like `v1.0.1-3-ge788140` — three commits past the tag. Such a build is
/// *ahead* of v1.0.1 and must not be told there is an update waiting.
struct Version: Equatable, Comparable {

    let components: [Int]

    /// Commits since the tag, from `git describe`. Zero for a released build.
    let commitsAhead: Int

    /// - Returns: nil for anything that does not begin with a number, once a
    ///   leading "v" is set aside. Better to know nothing than to invent an
    ///   ordering for a string nobody meant as a version.
    init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.lowercased().hasPrefix("v") { body.removeFirst() }

        // `git describe` appends "-<commits>-g<hash>", and a dirty tree "-dirty".
        let parts = body.split(separator: "-", omittingEmptySubsequences: false)
        guard let numbers = parts.first else { return nil }

        let fields = numbers.split(separator: ".").map { Int($0) }
        guard !fields.isEmpty, fields.allSatisfy({ $0 != nil }) else { return nil }
        components = fields.compactMap { $0 }

        commitsAhead = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        ordering(lhs, rhs) < 0
    }

    /// Written out rather than synthesised, so that equality agrees with
    /// ordering. Left to itself it would compare the arrays literally, making
    /// 1.0 and 1.0.0 unequal while neither is less than the other — a
    /// `Comparable` whose `==` disagrees with its `<` is a trap laid for
    /// whoever sorts a list of these next.
    static func == (lhs: Version, rhs: Version) -> Bool {
        ordering(lhs, rhs) == 0
    }

    /// Negative, zero or positive, as the left compares to the right.
    private static func ordering(_ lhs: Version, _ rhs: Version) -> Int {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            // Missing fields are zero: 1.0 and 1.0.0 are the same version.
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        if lhs.commitsAhead != rhs.commitsAhead {
            return lhs.commitsAhead < rhs.commitsAhead ? -1 : 1
        }
        return 0
    }
}
