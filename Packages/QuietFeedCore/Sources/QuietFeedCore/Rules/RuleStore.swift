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

public final class RuleStore {
    public enum Source: String, Codable, Equatable, Sendable {
        case bundled, cached, remote
    }

    public struct Status: Equatable {
        public var source: Source
        public var packVersion: Int
        public var lastFetchAt: Date?
        public var lastError: String?
    }

    public private(set) var activePack: RulePack
    public private(set) var status: Status
    public var serverURL: URL

    private let cache: JSONFileStore
    private let fetcher: RuleFetching
    private let now: () -> Date

    public static let defaultServerURL = URL(string: "http://your-server:8787/rulepack.json")!

    /// Load order: bundled pack, then the cached pack if it is valid and has a higher `packVersion`.
    public init(
        bundled: RulePack,
        cache: JSONFileStore,
        fetcher: RuleFetching,
        serverURL: URL = RuleStore.defaultServerURL,
        now: @escaping () -> Date = Date.init
    ) {
        self.cache = cache
        self.fetcher = fetcher
        self.serverURL = serverURL
        self.now = now
        self.activePack = bundled
        self.status = Status(source: .bundled, packVersion: bundled.packVersion, lastFetchAt: nil, lastError: nil)

        if let data = cache.readData(),
           case .success(let cached) = RulePackValidator.validate(data),
           cached.packVersion > bundled.packVersion {
            activePack = cached
            status.source = .cached
            status.packVersion = cached.packVersion
        }
    }

    /// Fetches the remote pack. A failure, an invalid pack or an older pack leaves the active
    /// pack unchanged. An accepted pack is cached and applies to the next page load.
    public func refresh() async {
        status.lastFetchAt = now()
        let data: Data
        do {
            data = try await fetcher.fetch(url: serverURL)
        } catch {
            status.lastError = "Could not fetch rules: \(error.localizedDescription)"
            return
        }
        switch RulePackValidator.validate(data) {
        case .failure(let error):
            status.lastError = "Rejected remote rules: \(error)"
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
            status.source = .remote
            status.packVersion = pack.packVersion
            status.lastError = nil
        }
    }
}
