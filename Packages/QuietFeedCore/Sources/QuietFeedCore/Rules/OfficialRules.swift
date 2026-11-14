import Foundation

/// Where the official, signed rule packs come from (Architecture 4.4 and 4.5).
public enum OfficialRules {
    /// Public GitHub Pages address, published by CI. The path carries the schema version.
    public static let url = URL(string: "https://rdaswav.github.io/quietfeed/v1/rulepack.json")!

    /// Raw 32 byte Ed25519 public keys by key id. Empty until the real key exists (T34). While it is empty the
    /// official source makes no network request at all, because nothing it returned could be trusted.
    public static let publicKeys: [String: Data] = [:]

    public static var verifier: PackVerifier { PackVerifier(publicKeys: publicKeys) }
}
