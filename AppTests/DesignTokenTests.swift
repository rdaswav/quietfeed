import XCTest

/// Keeps the asset catalog and the design tokens in step, and holds the contrast promises of the design system.
final class DesignTokenTests: XCTestCase {
    private struct Token: Decodable { let light: String; let dark: String }
    private struct File: Decodable {
        let colors: [String: Token]
        let contrast: [[Contrast]]
        enum Contrast: Decodable {
            case name(String), number(Double)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let n = try? c.decode(Double.self) { self = .number(n) } else { self = .name(try c.decode(String.self)) }
            }
        }
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func loadTokens() throws -> File {
        try JSONDecoder().decode(File.self, from: Data(contentsOf: root.appendingPathComponent("design/tokens.json")))
    }

    /// Reads a hex like "#F6F5F1" or "0xF6" parts from a colour set component.
    private func rgb(_ hex: String) -> (Double, Double, Double) {
        let h = hex.replacingOccurrences(of: "#", with: "")
        let v = UInt32(h, radix: 16)!
        return (Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255))
    }

    private func luminance(_ hex: String) -> Double {
        let (r, g, b) = rgb(hex)
        func f(_ c: Double) -> Double {
            let s = c / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }

    private func ratio(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func catalogHex(_ name: String, dark: Bool) throws -> String {
        let url = root.appendingPathComponent("App/Resources/Assets.xcassets/\(name).colorset/Contents.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let colors = json["colors"] as! [[String: Any]]
        let entry = colors.first { ($0["appearances"] != nil) == dark }!
        let comps = (entry["color"] as! [String: Any])["components"] as! [String: String]
        func byte(_ key: String) -> String { String(comps[key]!.dropFirst(2)) }
        return "#" + byte("red") + byte("green") + byte("blue")
    }

    func testEveryColourSetMatchesTheTokensFile() throws {
        let tokens = try loadTokens().colors
        XCTAssertFalse(tokens.isEmpty)
        for (name, t) in tokens {
            XCTAssertEqual(try catalogHex(name, dark: false).uppercased(), t.light.uppercased(), "\(name) light")
            XCTAssertEqual(try catalogHex(name, dark: true).uppercased(), t.dark.uppercased(), "\(name) dark")
        }
    }

    func testTheContrastPromisesHoldInBothAppearances() throws {
        let file = try loadTokens()
        for pair in file.contrast {
            guard case .name(let fg) = pair[0], case .name(let bg) = pair[1], case .number(let need) = pair[2] else {
                return XCTFail("bad contrast entry")
            }
            XCTAssertGreaterThanOrEqual(ratio(file.colors[fg]!.light, file.colors[bg]!.light), need, "\(fg) on \(bg), light")
            XCTAssertGreaterThanOrEqual(ratio(file.colors[fg]!.dark, file.colors[bg]!.dark), need, "\(fg) on \(bg), dark")
        }
    }
}
