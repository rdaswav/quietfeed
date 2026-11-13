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
                            SiteTile(name: site.name)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(site.name), no limit")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(name)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("No limit")
                    .font(Theme.timeFont)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(maxWidth: .infinity, minHeight: Theme.tileHeight, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.line, lineWidth: Theme.hairline)
        )
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
