import SwiftUI
import WebKit
import QuietFeedCore

/// Lets the menu act on the web view that SiteWebView creates.
@Observable
final class BrowserController {
    @ObservationIgnored weak var webView: WKWebView?

    func reload() {
        webView?.reload()
    }

    func goHome(_ site: SiteRules) {
        guard let url = URL(string: site.homeURL) else { return }
        webView?.load(URLRequest(url: url))
    }

    func openInSafari(_ site: SiteRules) {
        guard let url = webView?.url ?? URL(string: site.homeURL) else { return }
        UIApplication.shared.open(url)
    }
}

struct BrowserView: View {
    let site: SiteRules
    let model: AppModel
    @State private var controller = BrowserController()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topBar
            SiteWebView(
                site: site,
                runtimeSource: SiteWebViewFactory.runtimeSource(),
                controller: controller,
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
            Menu {
                Button("Reload", systemImage: "arrow.clockwise") { controller.reload() }
                Button("Go to site home", systemImage: "house") { controller.goHome(site) }
                // "Pause filters" arrives in T16.
                Button("Open in Safari", systemImage: "safari") { controller.openInSafari(site) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.textMuted)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, Theme.gutter / 2)
        .frame(minHeight: 44)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: Theme.hairline)
        }
    }
}
