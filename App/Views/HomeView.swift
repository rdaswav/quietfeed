import SwiftUI
import QuietFeedCore

struct HomeView: View {
    let model: AppModel
    @State private var postGate = false
    @State private var postFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.tileGap) {
                    header
                    if let error = model.loadError {
                        Text(error)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.warn)
                    }
                    ForEach(model.sites, id: \.id) { site in
                        NavigationLink(value: site.id) {
                            BudgetCard(
                                name: site.name,
                                state: model.budgetState(for: site.id),
                                allowedSeconds: model.allowedSeconds(for: site.id),
                                rulesStale: model.isStale(site))
                        }
                        .buttonStyle(.plain)
                    }
                    footer
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .background(Theme.bg)
            .navigationDestination(for: String.self) { id in
                if let site = model.sites.first(where: { $0.id == id }) {
                    BrowserView(site: site, model: model)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: model.preloadFeeds) {
                guard model.preloadFeeds else { return }
                await WebViewCache.shared.warm(model.sites) { site in
                    if case .exhausted = model.budgetState(for: site.id) { return true }
                    return false
                }
            }
            .sheet(isPresented: $postGate) {
                FrictionGate(
                    title: "Open the official apps for \(AppModel.postModeMinutes) minutes?",
                    confirmLabel: "Open for \(AppModel.postModeMinutes) min",
                    countdownSeconds: model.frictionCountdownSeconds,
                    phrase: model.limits.frictionPhrase,
                    onConfirm: {
                        postGate = false
                        postFailed = !model.startPostMode()
                    },
                    onCancel: { postGate = false }
                )
            }
        }
        .tint(Theme.accent)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                QuietFeedMark(size: 28)
                Text("Quiet Feed")
                    .font(Theme.wordmarkFont)
                    .foregroundStyle(Theme.text)
                Spacer()
                NavigationLink {
                    SettingsView(model: model)
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: Theme.touchTarget, height: Theme.touchTarget)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.top, 8)
            Text("Your feeds, with an end.")
                .font(Theme.displayFont)
                .foregroundStyle(Theme.text)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            Text("Resets at \(model.resetTimeText)")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textMuted)
                .padding(.bottom, 10)
        }
    }

    // MARK: Footer: shield state and Post Mode

    @ViewBuilder
    private var footer: some View {
        if model.shieldEnabled, model.shieldAuthorization == .approved {
            VStack(spacing: 10) {
                if let ends = model.postModeEndsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(ends.timeIntervalSince(context.date)))
                        Chip(text: "Post Mode \u{00B7} \(TimeText.clock(left))", kind: .amber)
                            .accessibilityLabel("Post Mode, \(left) seconds left")
                    }
                    Text("The official apps are open until then.")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textMuted)
                } else {
                    HStack(spacing: 8) {
                        Chip(text: "Shielded")
                        Text("Official apps are blocked")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Button("Post Mode") { postGate = true }
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textMuted)
                        .frame(minHeight: Theme.touchTarget)
                    if postFailed {
                        Text("Post Mode could not start, so the shield stays on.")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.warn)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        }
    }
}

/// One site's time budget, in the three states of the design: time left, nearly there (amber, never red) and done.
private struct BudgetCard: View {
    let name: String
    let state: BudgetEngine.State
    let allowedSeconds: Int?
    let rulesStale: Bool

    private var isDone: Bool {
        if case .exhausted = state { return true }
        return false
    }

    private var isLow: Bool {
        if case .warning = state { return true }
        return false
    }

    private var remainingSeconds: Int? {
        switch state {
        case .ok(let r), .warning(let r): return r
        default: return nil
        }
    }

    private var fraction: Double {
        guard let r = remainingSeconds, let allowed = allowedSeconds, allowed > 0 else { return 0 }
        return Double(r) / Double(allowed)
    }

    private var valueText: String {
        switch state {
        case .unlimited: return "No limit"
        case .ok(let r), .warning(let r): return TimeText.minutes(r)
        case .exhausted: return "Done for today"
        }
    }

    private var captionText: String? {
        guard let allowed = allowedSeconds, remainingSeconds != nil else { return nil }
        return "left of \(allowed / 60)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(isDone ? Theme.textMuted : Theme.text)
                if rulesStale {
                    Circle().fill(Theme.warn).frame(width: 8, height: 8).accessibilityHidden(true)
                }
                Spacer()
                Text(valueText)
                    .font(isDone || valueText == "No limit" ? Theme.captionFont : Theme.timeFont)
                    .foregroundStyle(isLow ? Theme.warn : (isDone ? Theme.textMuted : Theme.text))
            }
            if case .unlimited = state {
                EmptyView()
            } else {
                TimeBar(fraction: fraction, tone: isDone ? .done : (isLow ? .amber : .sage))
                if let captionText {
                    Text(captionText)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietCard(muted: isDone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch state {
        case .unlimited: return "\(name), no limit"
        case .exhausted: return "\(name), done for today"
        case .ok(let r), .warning(let r):
            let of = allowedSeconds.map { ", of \($0 / 60) minutes" } ?? ""
            return "\(name), \(TimeText.minutes(r)) left\(of)"
        }
    }
}

#Preview("Light") {
    HomeView(model: AppModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HomeView(model: AppModel())
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    HomeView(model: AppModel())
        .dynamicTypeSize(.accessibility5)
}
