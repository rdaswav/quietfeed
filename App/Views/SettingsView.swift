import SwiftUI
import QuietFeedCore

private struct ShieldGate: Identifiable {
    let id = UUID()
    let title: String
    let action: () -> Void
}

private struct LimitGate: Identifiable {
    let id = UUID()
    let title: String
    let settings: LimitSettings
}

struct SettingsView: View {
    let model: AppModel
    @State private var serverText = ""
    @State private var serverInvalid = false
    @State private var phraseDraft = ""
    @State private var gate: LimitGate?
    @State private var draft = LimitDraft()
    @State private var shieldGate: ShieldGate?

    var body: some View {
        Form {
            pendingSection
            limitsSection
            frictionSection
            officialAppsSection
            rulesSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            serverText = model.serverURLText
            phraseDraft = model.limits.frictionPhrase
        }
        .onDisappear { draft.discard() }
        .sheet(item: $gate) { pending in
            FrictionGate(
                title: pending.title,
                countdownSeconds: model.frictionCountdownSeconds,
                phrase: model.limits.frictionPhrase,
                onConfirm: {
                    draft.applyPending(to: model)
                    phraseDraft = model.limits.frictionPhrase
                    gate = nil
                },
                // Cancelling keeps the waiting changes so they can be tried again or discarded.
                onCancel: { gate = nil }
            )
        }
        .sheet(item: $shieldGate) { pending in
            FrictionGate(
                title: pending.title,
                countdownSeconds: model.frictionCountdownSeconds,
                phrase: model.limits.frictionPhrase,
                onConfirm: { pending.action(); shieldGate = nil },
                onCancel: { shieldGate = nil }
            )
        }
    }

    // MARK: Limits and friction

    private var working: LimitSettings { draft.working(from: model.limits) }

    /// Tightening applies at once. Loosening waits in the draft and is applied together through one gate.
    private func change(_ edit: (inout LimitSettings) -> Void) {
        draft.edit(edit, model: model)
        if !draft.hasPending { phraseDraft = model.limits.frictionPhrase }
    }

    private func budgetBinding(_ site: SiteRules) -> Binding<Int> {
        Binding(
            get: { working.budgetMinutes(site: site.id) },
            set: { v in change { $0.dailyBudgetMinutesBySite[site.id] = v } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<LimitSettings, Int>) -> Binding<Int> {
        Binding(
            get: { working[keyPath: keyPath] },
            set: { v in change { $0[keyPath: keyPath] = v } }
        )
    }

    /// Shown only while loosening changes are waiting.
    @ViewBuilder
    private var pendingSection: some View {
        if draft.hasPending {
            let count = draft.waitingCount(from: model.limits)
            Section {
                Text(count == 1 ? "1 change is waiting." : "\(count) changes are waiting.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)
                    .listRowBackground(Theme.surface)
                Button {
                    if let pending = draft.pending {
                        gate = LimitGate(title: "Apply your changes to limits", settings: pending)
                    }
                } label: {
                    Text("Apply changes").foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.surface)
                Button {
                    draft.discard()
                    phraseDraft = model.limits.frictionPhrase
                } label: {
                    Text("Discard").foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.surface)
            } footer: {
                Text("These loosen your limits, so applying them asks you to wait once, for all of them together. Leaving this screen drops them.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var limitsSection: some View {
        Section {
            ForEach(model.sites, id: \.id) { site in
                stepperRow(site.name, value: budgetBinding(site), range: 0...180, step: 5) { v in
                    v == 0 ? "No limit" : "\(v) min"
                }
            }
            stepperRow("Extension length", value: intBinding(\.extensionMinutes),
                       range: 1...30, step: 1) { "\($0) min" }
            stepperRow("Extensions per day", value: intBinding(\.maxExtensionsPerDay),
                       range: 0...10, step: 1) { "\($0)" }
            stepperRow("Filter pauses per day", value: intBinding(\.maxFilterPausesPerDay),
                       range: 0...10, step: 1) { "\($0)" }
        } header: {
            Text("Daily limits").foregroundStyle(Theme.textMuted)
        } footer: {
            Text("Lowering a limit applies at once. Raising one waits until you apply it.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var frictionSection: some View {
        Section {
            stepperRow("Countdown", value: intBinding(\.frictionCountdownSeconds),
                       range: 5...120, step: 5) { "\($0) s" }
            VStack(alignment: .leading, spacing: 4) {
                Text("Phrase")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textMuted)
                TextField("Phrase", text: $phraseDraft)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()
                    .onSubmit { commitPhrase() }
            }
            .listRowBackground(Theme.surface)
        } header: {
            Text("Friction").foregroundStyle(Theme.textMuted)
        }
    }

    private func commitPhrase() {
        let trimmed = phraseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phraseDraft = model.limits.frictionPhrase
            return
        }
        change { $0.frictionPhrase = trimmed }
    }

    private func stepperRow(
        _ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int,
        format: @escaping (Int) -> String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title).font(Theme.bodyFont).foregroundStyle(Theme.text)
                Spacer()
                Text(format(value.wrappedValue)).font(Theme.timeFont).foregroundStyle(Theme.textMuted)
            }
        }
        .accessibilityValue(format(value.wrappedValue))
        .listRowBackground(Theme.surface)
    }

    // MARK: Official apps

    private var shieldBinding: Binding<Bool> {
        Binding(
            get: { model.shieldEnabled },
            set: { on in
                if on {
                    model.setShieldEnabled(true)
                } else {
                    shieldGate = ShieldGate(title: "Stop shielding the official apps") {
                        model.setShieldEnabled(false)
                    }
                }
            }
        )
    }

    private var officialAppsSection: some View {
        Section {
            row("Screen Time access", accessText)
            switch model.shieldAuthorization {
            case .notDetermined:
                Button {
                    Task { await model.requestShieldAccess() }
                } label: {
                    Text("Allow access").foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.surface)
            case .denied:
                Text("Turn Quiet Feed on under Settings, Screen Time, then come back.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textMuted)
                    .listRowBackground(Theme.surface)
            case .approved:
                chooseAppsRow
                Toggle(isOn: shieldBinding) {
                    Text("Shield official apps").font(Theme.bodyFont).foregroundStyle(Theme.text)
                }
                .tint(Theme.accent)
                .disabled(!model.shieldHasSelection && !model.shieldEnabled)
                .listRowBackground(Theme.surface)
                row("Post Mode length", "15 min")
            }
        } header: {
            Text("Official apps").foregroundStyle(Theme.textMuted)
        } footer: {
            Text("Shielded apps show a Screen Time screen when opened. Taking apps off the shield or switching it off asks you to wait first.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textMuted)
        }
    }

    @ViewBuilder
    private var chooseAppsRow: some View {
        #if canImport(FamilyControls)
        if let controller = model.shield as? FamilyShieldController {
            ChooseAppsRow(
                controller: controller,
                version: model.shieldVersion,
                onCommitted: { model.reconcileShield() },
                requestGate: { title, action in shieldGate = ShieldGate(title: title, action: action) }
            )
        } else {
            simulatorNote
        }
        #else
        simulatorNote
        #endif
    }

    private var simulatorNote: some View {
        Text("Choosing apps needs a real iPhone.")
            .font(Theme.captionFont)
            .foregroundStyle(Theme.textMuted)
            .listRowBackground(Theme.surface)
    }

    private var accessText: String {
        switch model.shieldAuthorization {
        case .notDetermined: return "Not asked"
        case .approved: return "Allowed"
        case .denied: return "Not allowed"
        }
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
                TextField("Optional, for example http://your-server:8787/rulepack.json", text: $serverText)
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
        case .official: return "Official, version \(s.packVersion)"
        case .custom: return "Custom server, version \(s.packVersion)"
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

#Preview("Largest text") {
    NavigationStack { SettingsView(model: AppModel()) }
        .dynamicTypeSize(.accessibility5)
}
