import SwiftUI
import QuietFeedCore

struct HomeView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.tileGap) {
                    if let error = model.loadError {
                        Text(error)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.warn)
                    }
                    ForEach(model.sites, id: \.id) { site in
                        NavigationLink(value: site.id) {
                            SiteTile(
                                name: site.name,
                                state: model.budgetState(for: site.id),
                                allowedSeconds: model.allowedSeconds(for: site.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, Theme.tileGap)
            }
            .background(Theme.bg)
            .navigationDestination(for: String.self) { id in
                if let site = model.sites.first(where: { $0.id == id }) {
                    BrowserView(site: site, model: model)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(model: model)
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Theme.textMuted)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarBackground(Theme.bg, for: .navigationBar)
        }
        .tint(Theme.accent)
    }
}

private struct SiteTile: View {
    let name: String
    let state: BudgetEngine.State
    let allowedSeconds: Int?

    private var valueText: String {
        switch state {
        case .unlimited: return "No limit"
        case .ok(let r), .warning(let r): return TimeText.minutes(r)
        case .exhausted: return "Done"
        }
    }

    private var valueColor: Color {
        switch state {
        case .warning: return Theme.warn
        default: return Theme.textMuted
        }
    }

    /// 0...1 share of today's time still left; nil hides the bar.
    private var fraction: Double? {
        switch state {
        case .unlimited: return nil
        case .exhausted: return 0
        case .ok(let r), .warning(let r):
            guard let allowed = allowedSeconds, allowed > 0 else { return nil }
            return min(1, Double(r) / Double(allowed))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(valueText)
                    .font(Theme.timeFont)
                    .foregroundStyle(valueColor)
            }
            if let fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(Theme.accent).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: Theme.barHeight)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(maxWidth: .infinity, minHeight: Theme.tileHeight, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.line, lineWidth: Theme.hairline)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(valueText == "Done" ? "\(name), done for today" : "\(name), \(valueText)")
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
