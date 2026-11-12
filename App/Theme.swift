import SwiftUI

/// Design tokens. Colours live in Assets.xcassets (light and dark values).
/// Views must use these and never literal colours or font sizes.
enum Theme {
    static let bg = Color("bg")
    static let surface = Color("surface")
    static let line = Color("line")
    static let text = Color("text")
    static let textMuted = Color("textMuted")
    static let accent = Color("accent")
    static let warn = Color("warn")

    static let titleFont = Font.title2.weight(.semibold)
    static let bodyFont = Font.body
    static let captionFont = Font.footnote
    static let timeFont = Font.body.monospacedDigit()

    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 10
    static let gutter: CGFloat = 20
    static let tileGap: CGFloat = 12
    static let tileHeight: CGFloat = 76
    static let barHeight: CGFloat = 3
    static let hairline: CGFloat = 1
}
