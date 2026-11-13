import Foundation

/// Reads and writes one JSON file atomically, creating parent directories as needed.
public struct JSONFileStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func readData() -> Data? {
        try? Data(contentsOf: url)
    }

    public func writeData(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func load<T: Decodable>(_ type: T.Type = T.self) -> T? {
        guard let data = readData() else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func save<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeData(try encoder.encode(value))
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
