import SwiftUI
import UIKit
import WebKit
import QuietFeedCore

/// Lets the menu act on the web view that SiteWebView creates.
@Observable
final class BrowserController {
    @ObservationIgnored weak var webView: WKWebView? {
        didSet {
            urlObservation = webView?.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                let path = view.url?.path ?? ""
                Task { @MainActor in self?.currentPath = path }
            }
        }
    }
    @ObservationIgnored private var urlObservation: NSKeyValueObservation?
    /// Path of the page on show, so the tab bar can mark the current tab.
    var currentPath = ""

    /// Opens a path on the site's own host.
    func open(path: String, on site: SiteRules) {
        guard let base = URL(string: site.homeURL), let url = URL(string: path, relativeTo: base) else { return }
        webView?.load(URLRequest(url: url.absoluteURL))
    }

    /// Opens the signed-in profile by pressing the profile tab in the site's own (hidden) bar.
    func openProfile() async {
        _ = try? await webView?.evaluateJavaScript("window.__qfOpenProfile ? window.__qfOpenProfile() : false")
    }

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
    var confirmLabel: String = "Continue"
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
    /// How many things were just hidden, shown for a few seconds as a quiet notice.
    @State private var hiddenNotice: Int?
    @State private var noticeTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    private var state: BudgetEngine.State { model.budgetState(for: site.id) }

    private var nav: SiteNav? { SiteNav.forSite(site.id) }

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
                    onHealth: { siteId, report in
                        model.recordHealth(report, for: siteId)
                        showNotice(for: report.hiddenCount)
                        #if DEBUG
                        // `-qfAutoOutline` saves the outline once the page has settled, with no menu to tap.
                        if UserDefaults.standard.bool(forKey: "qfAutoOutline") {
                            let delay = UserDefaults.standard.double(forKey: "qfAutoOutlineDelay")
                            Task {
                                try? await Task.sleep(for: .seconds(delay))
                                outlineNote = await controller.savePageOutline(siteId: siteId)
                            }
                        }
                        #endif
                    }
                )
                .overlay(alignment: .top) { noticeStrip }
                if hasLimit { bottomBar }
                if let nav { navBar(nav) }
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
                confirmLabel: request.confirmLabel,
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
        let minutes = model.limits.extensionMinutes
        return LimitOverlay(
            siteName: site.name,
            minutesUsed: allowed / 60,
            resetTimeText: model.resetTimeText,
            extensionMinutes: minutes,
            extensionsLeft: model.extensionsLeft(for: site.id),
            maxExtensions: model.limits.maxExtensionsPerDay,
            onHome: { dismiss() },
            onExtend: {
                gate = GateRequest(title: "Take \(minutes) more minutes?", confirmLabel: "Add \(minutes) min") {
                    model.grantExtension(siteId: site.id)
                }
            }
        )
    }

    private func requestFilterPause() {
        gate = GateRequest(title: "Pause the filters on \(site.name) for 5 minutes?", confirmLabel: "Pause filters") {
            model.recordFilterPause(siteId: site.id)
            controller.pauseFilters()
            pauseRemaining = AppModel.filterPauseSeconds
        }
    }

    // MARK: Quiet notice of what was hidden

    private func showNotice(for count: Int) {
        guard count > 0 else { return }
        noticeTask?.cancel()
        withAnimation { hiddenNotice = count }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { withAnimation { hiddenNotice = nil } }
        }
    }

    @ViewBuilder
    private var noticeStrip: some View {
        if let count = hiddenNotice {
            HStack(spacing: 10) {
                Image(systemName: "minus")
                    .font(Font.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(count == 1 ? "1 thing hidden" : "\(count) things hidden")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: Theme.hairline))
            .padding(.top, 12)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Top bar and usage bar

    private var hasLimit: Bool {
        if case .unlimited = state { return false }
        return true
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(Font.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: Theme.touchTarget, height: Theme.touchTarget)
            }
            .accessibilityLabel("Back to Home")
            if let paused = pauseRemaining {
                Text("Filters paused \(TimeText.clock(paused))")
                    .font(Theme.timeFont)
                    .foregroundStyle(Theme.warn)
            } else {
                Text(site.name)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            timeChip
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
                    .frame(width: Theme.touchTarget, height: Theme.touchTarget)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 52)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: Theme.hairline)
        }
        #if DEBUG
        .modifier(OutlineAlert(note: $outlineNote))
        #endif
    }

    /// "12:40 left" as a soft sage pill, amber when time is nearly up. Hidden when the site has no limit.
    @ViewBuilder
    private var timeChip: some View {
        switch state {
        case .unlimited:
            EmptyView()
        case .ok(let remaining):
            chip("\(TimeText.clock(remaining)) left", fill: Theme.accentSoft, ink: Theme.onAccentSoft,
                 label: "\(TimeText.minutes(remaining)) left")
        case .warning(let remaining):
            chip("\(TimeText.clock(remaining)) left", fill: Theme.warnSoft, ink: Theme.onWarnSoft,
                 label: "\(remaining) seconds left")
        case .exhausted:
            chip("Done", fill: Theme.warnSoft, ink: Theme.onWarnSoft, label: "Done for today")
        }
    }

    private func chip(_ text: String, fill: Color, ink: Color, label: String) -> some View {
        Text(text)
            .font(Font.system(size: 14, weight: .semibold).monospacedDigit())
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(fill, in: Capsule())
            .accessibilityLabel(label)
    }

    /// "Today's Instagram   17:20 of 30:00 used" with a thin bar.
    private var bottomBar: some View {
        let allowed = model.allowedSeconds(for: site.id) ?? 0
        let remaining: Int = {
            switch state {
            case .ok(let r), .warning(let r): return r
            default: return 0
            }
        }()
        let used = max(0, allowed - remaining)
        let low: Bool = { if case .warning = state { return true } else { return false } }()
        return VStack(spacing: 8) {
            HStack {
                Text("Today\u{2019}s \(site.name)")
                Spacer()
                Text("\(TimeText.clock(used)) of \(TimeText.clock(allowed)) used")
                    .monospacedDigit()
            }
            .font(Theme.captionFont)
            .foregroundStyle(Theme.textMuted)
            TimeBar(fraction: allowed > 0 ? Double(used) / Double(allowed) : 0, tone: low ? .amber : .sage, height: 4)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: Theme.hairline) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Our own tab bar (the site's is hidden)

    private func navBar(_ nav: SiteNav) -> some View {
        HStack(spacing: 0) {
            ForEach(nav.items) { item in
                let selected = item.matches(controller.currentPath)
                Button {
                    if item.isProfile {
                        Task { await controller.openProfile() }
                    } else if let path = item.path {
                        controller.open(path: path, on: site)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selected ? item.symbol + ".fill" : item.symbol)
                            .font(Font.system(size: 20, weight: .regular))
                        Text(item.label)
                            .font(Font.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selected ? Theme.accent : Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: Theme.hairline) }
    }
}
