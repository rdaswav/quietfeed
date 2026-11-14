import SwiftUI
import QuietFeedCore

/// First launch: three skippable pages. Shown once.
struct OnboardingView: View {
    let model: AppModel
    @State private var page = 0

    private let lastPage = 2

    init(model: AppModel) {
        self.model = model
        // The default dots are white, which vanish on the pale background.
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Theme.accent)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(Theme.line)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { model.completeOnboarding() }
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textMuted)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, Theme.gutter)

            TabView(selection: $page) {
                introPage.tag(0)
                limitsPage.tag(1)
                appsPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(page < lastPage ? "Next" : "Done") {
                if page < lastPage { page += 1 } else { model.completeOnboarding() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, Theme.gutter)
        }
        .background(Theme.bg)
    }

    private func pageLayout<Content: View>(
        _ title: String, _ message: String, @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QuietFeedMark(size: 36)
                Text(title)
                    .font(Theme.displayFont)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textMuted)
                content()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 1. What this is

    private var introPage: some View {
        pageLayout(
            "Quiet Feed",
            "Instagram, YouTube and Facebook, without the endless parts. You sign in to each site once."
        ) { EmptyView() }
    }

    // MARK: 2. Limits

    private var limitsPage: some View {
        pageLayout("Daily limits", "Choose how long each site can have you each day. You can change this later in Settings.") {
            VStack(spacing: Theme.tileGap) {
                ForEach(model.sites, id: \.id) { site in
                    budgetRow(site)
                }
            }
        }
    }

    private func budgetRow(_ site: SiteRules) -> some View {
        let binding = Binding<Int>(
            get: { model.limits.budgetMinutes(site: site.id) },
            set: { v in
                // First-time setup, so no friction: the gate is for changing a choice you already made.
                var new = model.limits
                new.dailyBudgetMinutesBySite[site.id] = v
                model.commitLimits(new)
            })
        return Stepper(value: binding, in: 0...180, step: 5) {
            HStack {
                Text(site.name).font(Theme.bodyFont).foregroundStyle(Theme.text)
                Spacer()
                Text(binding.wrappedValue == 0 ? "No limit" : "\(binding.wrappedValue) min")
                    .font(Theme.timeFont)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .accessibilityValue(binding.wrappedValue == 0 ? "No limit" : "\(binding.wrappedValue) minutes")
        .quietCard()
    }

    // MARK: 3. Official apps

    private var appsPage: some View {
        pageLayout(
            "The official apps",
            "Quiet Feed can use Screen Time to stop the official Instagram, YouTube and Facebook apps opening, so the filtered versions here are the way in. You can do this later."
        ) {
            VStack(alignment: .leading, spacing: Theme.tileGap) {
                switch model.shieldAuthorization {
                case .notDetermined:
                    outlineButton("Allow Screen Time access") {
                        Task { await model.requestShieldAccess() }
                    }
                case .denied:
                    Text("Turn Quiet Feed on under Settings, Screen Time, then choose your apps from Settings in Quiet Feed.")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textMuted)
                case .approved:
                    chooseApps
                }
                Button("Later") { model.completeOnboarding() }
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textMuted)
                    .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private var chooseApps: some View {
        #if canImport(FamilyControls)
        if let controller = model.shield as? FamilyShieldController {
            List {
                ChooseAppsRow(
                    controller: controller,
                    version: model.shieldVersion,
                    onCommitted: {
                        if controller.hasSelection { model.setShieldEnabled(true) } else { model.reconcileShield() }
                    },
                    requestGate: { _, action in action() }
                )
            }
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 56)
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
    }

    private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(SecondaryButtonStyle())
    }
}

#Preview("Light") {
    OnboardingView(model: AppModel()).preferredColorScheme(.light)
}

#Preview("Dark") {
    OnboardingView(model: AppModel()).preferredColorScheme(.dark)
}

#Preview("Largest text") {
    OnboardingView(model: AppModel()).dynamicTypeSize(.accessibility5)
}
