import SwiftUI

/// Covers the web view once today's time is used up.
struct LimitOverlay: View {
    let siteName: String
    let minutesUsed: Int
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
        VStack(spacing: 20) {
            Spacer()
            Text("That\u{2019}s today\u{2019}s \(siteName).")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("\(minutesUsed) minutes used.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textMuted)
            Button(action: onHome) {
                Text("Back to Home")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            }
            .padding(.top, 8)
            if extensionsLeft > 0 {
                VStack(spacing: 4) {
                    Button("Add \(extensionMinutes) minutes", action: onExtend)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textMuted)
                    Text("\(extensionsLeft) of \(maxExtensions) extensions left")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textMuted)
                }
            } else {
                Text("No extensions left today.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter * 1.5)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Extensions left") {
    LimitOverlay(siteName: "Instagram", minutesUsed: 20, extensionMinutes: 5, extensionsLeft: 1,
                 maxExtensions: 2, onHome: {}, onExtend: {})
}

#Preview("No extensions left") {
    LimitOverlay(siteName: "Instagram", minutesUsed: 30, extensionMinutes: 5, extensionsLeft: 0,
                 maxExtensions: 2, onHome: {}, onExtend: {})
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    LimitOverlay(siteName: "Instagram", minutesUsed: 20, extensionMinutes: 5, extensionsLeft: 1,
                 maxExtensions: 2, onHome: {}, onExtend: {})
        .dynamicTypeSize(.accessibility5)
}
