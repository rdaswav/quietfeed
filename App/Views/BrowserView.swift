import SwiftUI
import UIKit
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

    /// Removes the injected script and content rule lists, then reloads (Architecture 5.4).
    func pauseFilters() {
        guard let webView else { return }
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeAllContentRuleLists()
        webView.reload()
    }

    /// Puts the script and content rule lists back, then reloads.
    @MainActor
    func resumeFilters(_ site: SiteRules) async {
        guard let webView else { return }
        let controller = webView.configuration.userContentController
        controller.addUserScript(SiteWebViewFactory.userScript(
            site: site, runtimeSource: SiteWebViewFactory.runtimeSource()))
        if let list = await ContentRuleCompiler.compile(site: site) {
            controller.add(list)
        }
        webView.reload()
    }
}

private struct GateRequest: Identifiable {
    let id = UUID()
    let title: String
    let onConfirm: () -> Void
}

struct BrowserView: View {
    let site: SiteRules
    let model: AppModel
    @State private var controller = BrowserController()
    #if DEBUG
    @State private var outlineNote: String?
    #endif
    @State private var gate: GateRequest?
    @State private var pauseRemaining: Int?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    private var state: BudgetEngine.State { model.budgetState(for: site.id) }

    private var isExhausted: Bool {
        if case .exhausted = state { return true }
        return false
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                SiteWebView(
                    site: site,
                    runtimeSource: SiteWebViewFactory.runtimeSource(),
                    controller: controller,
                    onHealth: { siteId, report in model.recordHealth(report, for: siteId) }
                )
            }
            if isExhausted { limitOverlay }
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: scenePhase) { await countUse() }
        .onChange(of: isExhausted) { _, exhausted in
            if exhausted { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
        .onDisappear { model.flushUsage() }
        .sheet(item: $gate) { request in
            FrictionGate(
                title: request.title,
                countdownSeconds: model.frictionCountdownSeconds,
                phrase: model.limits.frictionPhrase,
                onConfirm: { gate = nil; request.onConfirm() },
                onCancel: { gate = nil }
            )
        }
    }

    // MARK: Counting (Architecture 6.2)

    /// Counts once a second while this screen is visible, the app is active and no overlay is showing.
    private func countUse() async {
        guard scenePhase == .active else {
            model.flushUsage()
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            if !isExhausted { model.tick(siteId: site.id) }
            await tickPause()
        }
    }

    /// Filter pauses run on the wall clock of this loop; budget time keeps counting during one.
    private func tickPause() async {
        guard let remaining = pauseRemaining else { return }
        if remaining <= 1 {
            pauseRemaining = nil
            await controller.resumeFilters(site)
        } else {
            pauseRemaining = remaining - 1
        }
    }

    // MARK: Overlay and gate

    private var limitOverlay: some View {
        let allowed = model.allowedSeconds(for: site.id) ?? 0
        return LimitOverlay(
            siteName: site.name,
            minutesUsed: allowed / 60,
            extensionMinutes: model.limits.extensionMinutes,
            extensionsLeft: model.extensionsLeft(for: site.id),
            maxExtensions: model.limits.maxExtensionsPerDay,
            onHome: { dismiss() },
            onExtend: {
                gate = GateRequest(title: "Add \(model.limits.extensionMinutes) minutes to \(site.name)") {
                    model.grantExtension(siteId: site.id)
                }
            }
        )
    }

    private func requestFilterPause() {
        gate = GateRequest(title: "Pause filters on \(site.name) for 5 minutes") {
            model.recordFilterPause(siteId: site.id)
            controller.pauseFilters()
            pauseRemaining = AppModel.filterPauseSeconds
        }
    }

    // MARK: Top bar

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
            if let paused = pauseRemaining {
                Text("Filters paused \(TimeText.clock(paused))")
                    .font(Theme.timeFont.weight(.semibold))
                    .foregroundStyle(Theme.warn)
            } else {
                Text(site.name)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            timeLabel
            Menu {
                Button("Reload", systemImage: "arrow.clockwise") { controller.reload() }
                Button("Go to site home", systemImage: "house") { controller.goHome(site) }
                Button("Pause filters (5 min)", systemImage: "pause.circle") { requestFilterPause() }
                    .disabled(pauseRemaining != nil || !model.canPauseFilters(for: site.id))
                Button("Open in Safari", systemImage: "safari") { controller.openInSafari(site) }
                Button("Report a broken rule", systemImage: "exclamationmark.bubble") {
                    if let url = model.brokenRuleReportURL(for: site) { UIApplication.shared.open(url) }
                }
                #if DEBUG
                Button("Save page outline", systemImage: "square.and.arrow.down") {
                    Task { outlineNote = await controller.savePageOutline(siteId: site.id) }
                }
                #endif
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
        #if DEBUG
        .modifier(OutlineAlert(note: $outlineNote))
        #endif
    }

    @ViewBuilder
    private var timeLabel: some View {
        switch state {
        case .unlimited:
            EmptyView()
        case .ok(let remaining):
            Text(TimeText.clock(remaining))
                .font(Theme.timeFont)
                .foregroundStyle(Theme.text)
                .accessibilityLabel("\(TimeText.minutes(remaining)) left")
        case .warning(let remaining):
            Text(TimeText.clock(remaining))
                .font(Theme.timeFont)
                .foregroundStyle(Theme.warn)
                .accessibilityLabel("\(remaining) seconds left")
        case .exhausted:
            Text(TimeText.clock(0))
                .font(Theme.timeFont)
                .foregroundStyle(Theme.warn)
        }
    }
}
