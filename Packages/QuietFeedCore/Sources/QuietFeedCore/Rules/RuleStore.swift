import Foundation

public protocol RuleFetching {
    func fetch(url: URL) async throws -> Data
}

public struct URLSessionRuleFetcher: RuleFetching {
    public struct BadStatus: Error { public let code: Int }

    public var timeout: TimeInterval
    private let session: URLSession

    public init(timeout: TimeInterval = 5, session: URLSession = .shared) {
        self.timeout = timeout
        self.session = session
    }

    public func fetch(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw BadStatus(code: http.statusCode)
        }
        return data
    }
}

/// Where rules are fetched from. Official packs must carry a valid signature. A custom server is the user's own
/// and serves a plain rule pack.
public enum RuleSource: Equatable, Sendable {
    case official
    case custom(URL)
}

public final class RuleStore {
    public enum Source: String, Codable, Equatable, Sendable {
        case bundled, cached, official, custom
    }

    public struct Status: Equatable {
        public var source: Source
        public var packVersion: Int
        public var lastFetchAt: Date?
        public var lastError: String?
    }

    private struct Rejection: Error { let message: String }

    public private(set) var activePack: RulePack
    public private(set) var status: Status
    public var ruleSource: RuleSource

    private let cache: JSONFileStore
    private let fetcher: RuleFetching
    private let verifier: PackVerifier
    private let officialURL: URL
    private let appVersion: String
    private let now: () -> Date

    /// Load order: bundled pack, then the cached pack if it is valid for the current source and newer.
    /// An official cache holds the signed envelope and is verified again here.
    public init(
        bundled: RulePack,
        cache: JSONFileStore,
        fetcher: RuleFetching,
        ruleSource: RuleSource = .official,
        verifier: PackVerifier = OfficialRules.verifier,
        officialURL: URL = OfficialRules.url,
        appVersion: String = "1.0",
        now: @escaping () -> Date = Date.init
    ) {
        self.cache = cache
        self.fetcher = fetcher
        self.ruleSource = ruleSource
        self.verifier = verifier
        self.officialURL = officialURL
        self.appVersion = appVersion
        self.now = now
        self.activePack = bundled
        self.status = Status(source: .bundled, packVersion: bundled.packVersion, lastFetchAt: nil, lastError: nil)

        if let data = cache.readData(),
           case .success(let cached) = Self.decode(data, source: ruleSource, verifier: verifier, appVersion: appVersion),
           cached.packVersion > bundled.packVersion {
            activePack = cached
            status.source = .cached
            status.packVersion = cached.packVersion
        }
    }

    /// Signature first (official only), then the pack validator, then the app version the pack needs.
    private static func decode(
        _ data: Data, source: RuleSource, verifier: PackVerifier, appVersion: String
    ) -> Result<RulePack, Rejection> {
        let payload: Data
        switch source {
        case .official:
            switch verifier.verify(data) {
            case .success(let bytes): payload = bytes
            case .failure(let error): return .failure(Rejection(message: "Rejected official rules: \(error)"))
            }
        case .custom:
            payload = data
        }
        switch RulePackValidator.validate(payload) {
        case .failure(let error):
            return .failure(Rejection(message: "Rejected remote rules: \(error)"))
        case .success(let pack):
            if let need = pack.minAppVersion, !AppVersion.satisfies(current: appVersion, required: need) {
                return .failure(Rejection(message: "These rules need a newer version of the app (\(need))"))
            }
            return .success(pack)
        }
    }

    /// Fetches the pack from the current source. A failure, an invalid or unsigned pack, an older pack or a pack
    /// that needs a newer app leaves the active pack unchanged. An accepted pack is cached and applies to the
    /// next page load. The official source does nothing until the app has a public key for it.
    public func refresh() async {
        let url: URL
        let newSource: Source
        switch ruleSource {
        case .official:
            guard !verifier.publicKeys.isEmpty else { return }
            url = officialURL
            newSource = .official
        case .custom(let custom):
            url = custom
            newSource = .custom
        }
        status.lastFetchAt = now()
        let data: Data
        do {
            data = try await fetcher.fetch(url: url)
        } catch {
            status.lastError = "Could not fetch rules: \(error.localizedDescription)"
            return
        }
        switch Self.decode(data, source: ruleSource, verifier: verifier, appVersion: appVersion) {
        case .failure(let rejection):
            status.lastError = rejection.message
        case .success(let pack):
            guard pack.packVersion >= activePack.packVersion else {
                status.lastError = "Ignored older remote rules (version \(pack.packVersion))"
                return
            }
            do {
                try cache.writeData(data)
            } catch {
                status.lastError = "Could not cache rules: \(error.localizedDescription)"
                return
            }
            activePack = pack
            status.source = newSource
            status.packVersion = pack.packVersion
            status.lastError = nil
        }
    }
}
