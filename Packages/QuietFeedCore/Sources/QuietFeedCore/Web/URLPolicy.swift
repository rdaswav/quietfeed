import Foundation

public enum URLPolicy {
    public enum Decision: Equatable, Sendable {
        case allow
        case cancel
        case openExternally
        case redirect(URL)
    }

    public static func decide(url: URL, site: SiteRules, isMainFrame: Bool) -> Decision {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .cancel
        }
        if !isMainFrame { return .allow }
        guard let host = url.host?.lowercased(), hostAllowed(host, allowed: site.allowedHosts) else {
            return .openExternally
        }
        let path = url.path.isEmpty ? "/" : url.path
        for rule in site.pathRules {
            guard let re = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let range = NSRange(path.startIndex..., in: path)
            guard let match = re.firstMatch(in: path, range: range) else { continue }
            switch rule.action {
            case .block:
                return .cancel
            case .redirect:
                guard let to = rule.to, let target = redirectURL(from: url, to: to, path: path, match: match) else {
                    return .cancel
                }
                return .redirect(target)
            }
        }
        return .allow
    }

    /// Exact match or dot-prefixed subdomain. `evil-youtube.com` does not match `youtube.com`.
    static func hostAllowed(_ host: String, allowed: [String]) -> Bool {
        allowed.contains { a in
            let a = a.lowercased()
            return host == a || host.hasSuffix("." + a)
        }
    }

    private static func redirectURL(from url: URL, to: String, path: String, match: NSTextCheckingResult) -> URL? {
        var out = ""
        let chars = Array(to)
        var i = 0
        while i < chars.count {
            if chars[i] == "$", i + 1 < chars.count, let n = chars[i + 1].wholeNumberValue, (1...9).contains(n) {
                if n < match.numberOfRanges, let r = Range(match.range(at: n), in: path) {
                    out += path[r]
                }
                i += 2
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        var comps = URLComponents()
        comps.scheme = url.scheme
        comps.host = url.host
        comps.port = url.port
        guard let parsed = URLComponents(string: out) else { return nil }
        comps.percentEncodedPath = parsed.percentEncodedPath
        comps.percentEncodedQuery = parsed.percentEncodedQuery
        comps.percentEncodedFragment = parsed.percentEncodedFragment
        return comps.url
    }
}
