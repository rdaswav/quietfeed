import SwiftUI

/// Design tokens from the Quiet Feed design system (Direction A, Sage Paper).
/// Colours live in Assets.xcassets and are generated from design/tokens.json.
/// Views must use these and never literal colours or font sizes.
enum Theme {
    // Colour
    static let bg = Color("bg")
    static let surface = Color("surface")
    static let surfaceMuted = Color("surfaceMuted")
    static let line = Color("line")
    static let lineStrong = Color("lineStrong")
    static let text = Color("text")
    static let textMuted = Color("textMuted")
    static let accent = Color("accent")
    static let onAccent = Color("onAccent")
    static let accentSoft = Color("accentSoft")
    static let onAccentSoft = Color("onAccentSoft")
    static let warn = Color("warn")
    static let warnSoft = Color("warnSoft")
    static let onWarnSoft = Color("onWarnSoft")

    // Type. New York (the system serif) for display moments only, SF Pro for everything else.
    static let displayFont = Font.system(.largeTitle, design: .serif, weight: .medium)        // 34
    static let displayLargeFont = Font.system(size: 46, weight: .medium, design: .serif)      // limit reached
    static let sheetTitleFont = Font.system(.title, design: .serif, weight: .medium)          // 28, close to 26
    static let wordmarkFont = Font.system(.body, design: .serif, weight: .medium)             // 17
    static let titleFont = Font.title2.weight(.semibold)                                      // 22
    static let numberFont = Font.system(size: 40, weight: .semibold).monospacedDigit()
    static let bodyFont = Font.body                                                           // 17
    static let rowFont = Font.system(.callout, weight: .medium)                               // 16
    static let captionFont = Font.footnote.weight(.medium)                                    // 13
    static let labelFont = Font.system(size: 12, weight: .semibold)
    static let timeFont = Font.body.weight(.semibold).monospacedDigit()

    // Shape and space. 4 pt base, 20 pt margin, 44 pt minimum touch target.
    static let chipRadius: CGFloat = 10
    static let buttonRadius: CGFloat = 14
    static let cardRadius: CGFloat = 20
    static let fieldRadius: CGFloat = 12
    static let gutter: CGFloat = 20
    static let tileGap: CGFloat = 12
    static let primaryButtonHeight: CGFloat = 52
    static let buttonHeight: CGFloat = 48
    static let touchTarget: CGFloat = 44
    static let barHeight: CGFloat = 6
    static let hairline: CGFloat = 1
}
