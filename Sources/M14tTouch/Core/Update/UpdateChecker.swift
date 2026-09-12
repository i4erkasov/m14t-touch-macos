import Foundation

/// Asks GitHub whether a newer release exists.
///
/// Only when asked. Nothing here runs on a timer and nothing is sent: the
/// request is an ordinary anonymous read of a public endpoint, and the only
/// thing it reveals is that someone looked.
struct UpdateChecker {

    enum Outcome: Equatable {
        case upToDate(current: String)
        case updateAvailable(latest: String, url: String)
        case unknown(reason: String)
    }

    /// The releases API for this project. Public, unauthenticated, and rate
    /// limited generously enough for a button nobody presses twice.
    static let endpoint = URL(
        string: "https://api.github.com/repos/i4erkasov/m14t-touch-macos/releases/latest"
    )!

    /// Injected so the comparison can be tested without the network — which is
    /// the part with a decision in it.
    var fetch: (@Sendable () async throws -> (tag: String, url: String)) = {
        var request = URLRequest(url: UpdateChecker.endpoint)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct Release: Decodable {
            let tagName: String
            let htmlURL: String
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
            }
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        return (release.tagName, release.htmlURL)
    }

    func check(current: String?) async -> Outcome {
        guard let current, let mine = Version(current) else {
            return .unknown(reason: "This build has no version to compare")
        }
        do {
            let latest = try await fetch()
            guard let theirs = Version(latest.tag) else {
                return .unknown(reason: "The latest release has no version to compare")
            }
            // Strictly newer, so a development build three commits past the tag
            // is not told to downgrade to the tag it was built from.
            return theirs > mine
                ? .updateAvailable(latest: latest.tag, url: latest.url)
                : .upToDate(current: current)
        } catch {
            return .unknown(reason: "Could not reach GitHub")
        }
    }
}
