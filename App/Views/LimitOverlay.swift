import SwiftUI

/// Covers the web view once today's time is used up. Calm, not a scolding.
struct LimitOverlay: View {
    let siteName: String
    let minutesUsed: Int
    let resetTimeText: String
    let extensionMinutes: Int
    let extensionsLeft: Int
    let maxExtensions: Int
    let onHome: () -> Void
    let onExtend: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView { content.frame(minHeight: geo.size.height) }
                .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.bg)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuietFeedMark(size: 32)
                .padding(.top, 24)
            Spacer(minLength: 48)
            Text("That\u{2019}s today\u{2019}s \(siteName).")
                .font(Theme.displayLargeFont)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("You used \(minutesUsed) minutes. It\u{2019}s back tomorrow at \(resetTimeText).")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 14)
            Button("Done for today", action: onHome)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 36)
            if extensionsLeft > 0 {
                VStack(spacing: 2) {
                    Button("Need more time?", action: onExtend)
                        .buttonStyle(LinkButtonStyle())
                    Text("\(extensionsLeft) of \(maxExtensions) extensions left")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            } else {
                Text("No extensions left today.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Extensions left") {
    LimitOverlay(siteName: "Instagram", minutesUsed: 30, resetTimeText: "6:00 am", extensionMinutes: 5,
                 extensionsLeft: 1, maxExtensions: 2, onHome: {}, onExtend: {})
}

#Preview("No extensions left, dark") {
    LimitOverlay(siteName: "Instagram", minutesUsed: 30, resetTimeText: "6:00 am", extensionMinutes: 5,
                 extensionsLeft: 0, maxExtensions: 2, onHome: {}, onExtend: {})
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    LimitOverlay(siteName: "Instagram", minutesUsed: 30, resetTimeText: "6:00 am", extensionMinutes: 5,
                 extensionsLeft: 1, maxExtensions: 2, onHome: {}, onExtend: {})
        .dynamicTypeSize(.accessibility5)
}
