import Foundation

/// Version strings like "1", "1.2" or "1.2.3".
public enum AppVersion {
    /// Numeric components, or nil if the text is not 1 to 3 dot separated numbers.
    public static func parse(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var out: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.allSatisfy({ $0 >= "0" && $0 <= "9" }), let n = Int(p) else { return nil }
            out.append(n)
        }
        return out
    }

    /// True when `current` is the same as or newer than `required`. Missing components count as 0.
    /// An unreadable version on either side is treated as not satisfying, so a broken string never lets a pack in.
    public static func satisfies(current: String, required: String) -> Bool {
        guard var a = parse(current), var b = parse(required) else { return false }
        while a.count < 3 { a.append(0) }
        while b.count < 3 { b.append(0) }
        return a.lexicographicallyPrecedes(b) == false
    }
}
