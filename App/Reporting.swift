import Foundation

/// Builds the address that opens a prefilled GitHub issue for a rule that stopped working.
/// By construction it can only carry the fields below: no page URLs, no page text, no names, no query strings.
/// The user sees GitHub's form and decides whether to submit.
enum BrokenRuleReport {
    struct Input: Equatable {
        var siteId: String
        var siteName: String
        var appVersion: String
        var packVersion: Int
        /// "official", "custom server", "saved copy" or "built in".
        var rulesSource: String
        /// What the page health check found on the home page: "all found", "something missing" or "not checked yet".
        var health: String
    }

    static let base = "https://github.com/rdaswav/quietfeed/issues/new"

    static func url(_ input: Input) -> URL? {
        let body = """
        Describe what is showing that should be hidden, or what is broken:

        (Please do not include passwords, messages or other private content. A screenshot with names covered is fine.)

        ---
        Site: \(input.siteName) (\(input.siteId))
        App version: \(input.appVersion)
        Rules version: \(input.packVersion)
        Rules from: \(input.rulesSource)
        Page check: \(input.health)
        """
        var parts = URLComponents(string: base)
        parts?.queryItems = [
            URLQueryItem(name: "title", value: "Broken rules: \(input.siteName)"),
            URLQueryItem(name: "body", value: body),
        ]
        return parts?.url
    }
}
