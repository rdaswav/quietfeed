import SwiftUI
import QuietFeedCore

struct SettingsView: View {
    let model: AppModel
    @State private var serverText = ""
    @State private var serverInvalid = false

    var body: some View {
        Form {
            rulesSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { serverText = model.serverURLText }
    }

    // MARK: Rules

    private var rulesSection: some View {
        Section {
            row("Source", sourceText)
            row("Last checked", lastCheckedText)
            if let error = model.ruleStatus?.lastError {
                Text(error)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textMuted)
                    .listRowBackground(Theme.surface)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Server address")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textMuted)
                TextField("http://your-server:8787/rulepack.json", text: $serverText)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { commitServer() }
                if serverInvalid {
                    Text("Enter an address starting with http:// or https://")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.warn)
                }
            }
            .listRowBackground(Theme.surface)
            Button {
                commitServer()
                Task { await model.refreshRules() }
            } label: {
                HStack {
                    Text("Check now").foregroundStyle(Theme.accent)
                    Spacer()
                    if model.isChecking { ProgressView() }
                }
            }
            .disabled(model.isChecking)
            .listRowBackground(Theme.surface)
            ForEach(model.sites, id: \.id) { site in
                Text(healthText(for: site))
                    .font(Theme.bodyFont)
                    .foregroundStyle(model.isStale(site) ? Theme.warn : Theme.text)
                    .listRowBackground(Theme.surface)
            }
        } header: {
            Text("Rules").foregroundStyle(Theme.textMuted)
        }
    }

    private var aboutSection: some View {
        Section {
            row("Version", appVersion)
            Text("Nothing leaves your phone. The only network call is the rules check on your own network.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textMuted)
                .listRowBackground(Theme.surface)
        } header: {
            Text("About").foregroundStyle(Theme.textMuted)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(Theme.bodyFont).foregroundStyle(Theme.text)
            Spacer()
            Text(value).font(Theme.bodyFont).foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .combine)
        .listRowBackground(Theme.surface)
    }

    private func commitServer() {
        serverInvalid = !model.setServerURL(serverText)
        if !serverInvalid { serverText = model.serverURLText }
    }

    // MARK: Text

    private var sourceText: String {
        guard let s = model.ruleStatus else { return "Unavailable" }
        switch s.source {
        case .bundled: return "Built in, version \(s.packVersion)"
        case .cached: return "Saved copy, version \(s.packVersion)"
        case .remote: return "NAS, version \(s.packVersion)"
        }
    }

    private var lastCheckedText: String {
        guard let date = model.ruleStatus?.lastChecked else { return "Not yet" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func healthText(for site: SiteRules) -> String {
        if model.isStale(site) { return "\(site.name): rules may be stale" }
        if model.healthReports[site.id] == nil { return "\(site.name): not checked yet" }
        return "\(site.name): OK"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

#Preview("Light") {
    NavigationStack { SettingsView(model: AppModel()) }
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack { SettingsView(model: AppModel()) }
        .preferredColorScheme(.dark)
}
