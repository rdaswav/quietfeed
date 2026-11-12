import Foundation

/// Arbitrary JSON value, used to keep `contentRules` as raw entries.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

public struct PathRule: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case redirect
        case block
    }

    public var pattern: String
    public var action: Action
    public var to: String?

    public init(pattern: String, action: Action, to: String? = nil) {
        self.pattern = pattern
        self.action = action
        self.to = to
    }
}

public struct TextRule: Codable, Equatable, Sendable {
    public var text: String
    public var within: String?
    public var closest: String

    public init(text: String, within: String? = nil, closest: String) {
        self.text = text
        self.within = within
        self.closest = closest
    }
}

public struct SiteRules: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var homeURL: String
    public var allowedHosts: [String]
    public var pathRules: [PathRule]
    public var hideSelectors: [String]
    public var hideByText: [TextRule]
    public var contentRules: [JSONValue]
    public var canaries: [String]

    public init(
        id: String, name: String, homeURL: String, allowedHosts: [String],
        pathRules: [PathRule] = [], hideSelectors: [String] = [],
        hideByText: [TextRule] = [], contentRules: [JSONValue] = [],
        canaries: [String] = []
    ) {
        self.id = id
        self.name = name
        self.homeURL = homeURL
        self.allowedHosts = allowedHosts
        self.pathRules = pathRules
        self.hideSelectors = hideSelectors
        self.hideByText = hideByText
        self.contentRules = contentRules
        self.canaries = canaries
    }
}

public struct RulePack: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var packVersion: Int
    public var updated: String
    public var sites: [SiteRules]

    public init(schemaVersion: Int, packVersion: Int, updated: String, sites: [SiteRules]) {
        self.schemaVersion = schemaVersion
        self.packVersion = packVersion
        self.updated = updated
        self.sites = sites
    }
}
