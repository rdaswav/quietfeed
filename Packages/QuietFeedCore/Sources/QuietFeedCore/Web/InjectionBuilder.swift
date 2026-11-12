import Foundation

public enum InjectionBuilder {
    private struct Config: Encodable {
        let siteId: String
        let pathRules: [PathRule]
        let hideSelectors: [String]
        let hideByText: [TextRule]
        let canaries: [String]
    }

    /// Returns `window.__QF_CONFIG__ = <json>;\n` followed by the runtime source.
    public static func script(for site: SiteRules, runtimeSource: String) -> String {
        let config = Config(
            siteId: site.id,
            pathRules: site.pathRules,
            hideSelectors: site.hideSelectors,
            hideByText: site.hideByText,
            canaries: site.canaries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(config)) ?? Data("{}".utf8)
        var json = String(decoding: data, as: UTF8.self)
        // U+2028 and U+2029 are valid in JSON but were line terminators in JS before ES2019.
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        json = json.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "window.__QF_CONFIG__ = \(json);\n\(runtimeSource)"
    }
}
