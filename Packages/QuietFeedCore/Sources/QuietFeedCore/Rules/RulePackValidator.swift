import Foundation

public enum ValidationError: Error, Equatable, Sendable {
    case tooLarge(bytes: Int)
    case malformed(String)
    case unknownSchemaVersion(Int)
    case tooManySites(Int)
    case unknownSiteId(String)
    case listTooLong(site: String, list: String, count: Int)
    case invalidRegex(site: String, pattern: String)
    case redirectTarget(site: String, to: String?)
    case invalidSelector(site: String, selector: String)
    case homeURLNotHTTPS(site: String, url: String)
    case homeHostNotAllowed(site: String, host: String)
}

public enum RulePackValidator {
    public static let maxBytes = 256 * 1024
    public static let maxSites = 10
    public static let maxListEntries = 200
    public static let maxSelectorLength = 300
    public static let knownSiteIds: Set<String> = ["instagram", "youtube", "facebook"]
    /// ">" is allowed as the CSS child combinator. The rest can break out of a CSS rule or a tag.
    public static let forbiddenSelectorCharacters = Set("{}<;")

    public static func validate(_ data: Data) -> Result<RulePack, ValidationError> {
        if data.count >= maxBytes { return .failure(.tooLarge(bytes: data.count)) }
        let pack: RulePack
        do {
            pack = try JSONDecoder().decode(RulePack.self, from: data)
        } catch {
            return .failure(.malformed(String(describing: error)))
        }
        if let e = check(pack) { return .failure(e) }
        return .success(pack)
    }

    static func check(_ pack: RulePack) -> ValidationError? {
        if pack.schemaVersion != 1 { return .unknownSchemaVersion(pack.schemaVersion) }
        if pack.sites.count > maxSites { return .tooManySites(pack.sites.count) }
        for s in pack.sites {
            if !knownSiteIds.contains(s.id) { return .unknownSiteId(s.id) }
            let lists: [(String, Int)] = [
                ("allowedHosts", s.allowedHosts.count), ("pathRules", s.pathRules.count),
                ("hideSelectors", s.hideSelectors.count), ("hideByText", s.hideByText.count),
                ("contentRules", s.contentRules.count), ("canaries", s.canaries.count),
            ]
            for (name, n) in lists where n > maxListEntries {
                return .listTooLong(site: s.id, list: name, count: n)
            }
            for r in s.pathRules {
                if (try? NSRegularExpression(pattern: r.pattern)) == nil {
                    return .invalidRegex(site: s.id, pattern: r.pattern)
                }
                if r.action == .redirect, !(r.to?.hasPrefix("/") ?? false) {
                    return .redirectTarget(site: s.id, to: r.to)
                }
            }
            var selectors = s.hideSelectors + s.canaries
            for t in s.hideByText {
                selectors.append(t.closest)
                if let w = t.within { selectors.append(w) }
            }
            for sel in selectors where !selectorOK(sel) {
                return .invalidSelector(site: s.id, selector: sel)
            }
            guard let url = URL(string: s.homeURL), url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(), !host.isEmpty else {
                return .homeURLNotHTTPS(site: s.id, url: s.homeURL)
            }
            let covered = s.allowedHosts.contains { a in
                let a = a.lowercased()
                return host == a || host.hasSuffix("." + a)
            }
            if !covered { return .homeHostNotAllowed(site: s.id, host: host) }
        }
        return nil
    }

    static func selectorOK(_ s: String) -> Bool {
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if s.count >= maxSelectorLength { return false }
        return !s.contains { forbiddenSelectorCharacters.contains($0) }
    }
}
