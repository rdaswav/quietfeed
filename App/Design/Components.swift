import SwiftUI

// The few parts of the design system, used the same way everywhere.

// MARK: Mark

/// The Quiet Feed mark: two faint lines (the scroll) and one solid line (the end of it).
struct QuietFeedMark: View {
    var size: CGFloat = 28

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 64
            context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 64 * s, height: 64 * s), cornerRadius: 16 * s),
                         with: .color(Theme.accent))
            func line(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ alpha: Double) {
                context.fill(Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: h * s / 2),
                             with: .color(Theme.onAccent.opacity(alpha)))
            }
            line(16, 19, 26, 4, 0.4)
            line(16, 29, 18, 4, 0.4)
            line(16, 43, 32, 5, 1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: Buttons

/// One primary per screen: a sage fill with an onAccent label. Disabled looks like a quiet grey, not a dim sage.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyFont.weight(.semibold))
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.textMuted)
            .frame(maxWidth: .infinity, minHeight: Theme.primaryButtonHeight)
            .background(isEnabled ? Theme.accent : Theme.line, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Outlined, for the second choice on a screen.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyFont.weight(.semibold))
            .foregroundStyle(isEnabled ? Theme.text : Theme.textMuted)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .background(isEnabled ? Theme.surface : Theme.line, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.lineStrong, lineWidth: Theme.hairline))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A quiet underlined text button. Extending time is always this, never a primary button.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyFont.weight(.medium))
            .foregroundStyle(Theme.accent)
            .underline()
            .frame(minHeight: Theme.touchTarget)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: Chips

/// Small status labels: SHIELDED, POST MODE, RULES UPDATED.
struct Chip: View {
    enum Kind { case sage, amber, outline }

    let text: String
    var kind: Kind = .sage

    private var fill: Color {
        switch kind {
        case .sage: return Theme.accentSoft
        case .amber: return Theme.warnSoft
        case .outline: return Theme.surface
        }
    }

    private var ink: Color {
        switch kind {
        case .sage: return Theme.onAccentSoft
        case .amber: return Theme.onWarnSoft
        case .outline: return Theme.textMuted
        }
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.labelFont)
            .tracking(0.7)
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
            .overlay {
                if kind == .outline {
                    RoundedRectangle(cornerRadius: Theme.chipRadius).stroke(Theme.line, lineWidth: Theme.hairline)
                }
            }
    }
}

// MARK: Cards and bars

extension View {
    /// Surface, hairline border, 20 pt corners. Depth comes from the hairline, never a shadow.
    func quietCard(muted: Bool = false) -> some View {
        padding(.horizontal, Theme.gutter)
            .padding(.vertical, 18)
            .background(muted ? Theme.surfaceMuted : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.line, lineWidth: Theme.hairline))
    }

    /// The small uppercase label above a group, in sage.
    func sectionLabel() -> some View {
        font(Theme.labelFont)
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.accent)
    }
}

/// A thin time bar. Sage normally, amber when time is nearly up, never red.
struct TimeBar: View {
    enum Tone { case sage, amber, done }

    let fraction: Double
    var tone: Tone = .sage
    var height: CGFloat = Theme.barHeight

    private var track: Color {
        switch tone {
        case .sage: return Theme.accentSoft
        case .amber: return Theme.warnSoft
        case .done: return Theme.line
        }
    }

    private var fill: Color { tone == .amber ? Theme.warn : Theme.accent }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if tone != .done {
                    Capsule().fill(fill).frame(width: geo.size.width * max(0, min(1, fraction)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
