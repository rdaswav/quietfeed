import SwiftUI
import QuietFeedCore

struct BrowserView: View {
    let site: SiteRules
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topBar
            SiteWebView(
                site: site,
                runtimeSource: SiteWebViewFactory.runtimeSource(),
                onHealth: { siteId, report in model.recordHealth(report, for: siteId) }
            )
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Back to Home")
            Text(site.name)
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, Theme.gutter / 2)
        .frame(minHeight: 44)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: Theme.hairline)
        }
    }
}
