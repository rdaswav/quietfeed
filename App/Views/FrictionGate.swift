import SwiftUI
import QuietFeedCore

/// The one gate for every loosening action: a short wait, then a typed phrase. On purpose.
struct FrictionGate: View {
    let title: String
    var confirmLabel: String = "Continue"
    let countdownSeconds: Int
    let phrase: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var remaining: Int
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(title: String, confirmLabel: String = "Continue", countdownSeconds: Int, phrase: String,
         onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.countdownSeconds = countdownSeconds
        self.phrase = phrase
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _remaining = State(initialValue: countdownSeconds)
    }

    private var phraseMatches: Bool {
        FrictionPolicy.phraseMatches(typed: typed, phrase: phrase)
    }

    private var waiting: Bool { remaining > 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(Theme.sheetTitleFont)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text("It takes a short wait and a typed phrase. That\u{2019}s on purpose.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textMuted)
                countdownRow
                phraseField
                HStack(spacing: 12) {
                    Button(confirmLabel, action: onConfirm)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(waiting || !phraseMatches)
                    Button("Never mind", action: onCancel)
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.bg)
        .task(id: scenePhase) { await runCountdown() }
    }

    private var countdownRow: some View {
        HStack(spacing: 14) {
            Text(TimeText.clock(remaining))
                .font(Font.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.onAccentSoft)
                .frame(width: 56, height: 56)
                .background(Theme.accentSoft, in: Circle())
                .accessibilityLabel(waiting ? "\(remaining) seconds left" : "Done waiting")
            Text(waiting
                 ? "Waiting. Leaving the app restarts the timer."
                 : "Done waiting. Type the phrase to continue.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var phraseField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type: \(phrase)")
                .font(Theme.captionFont.weight(.semibold))
                .foregroundStyle(Theme.text)
            TextField(phrase, text: $typed)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
                .focused($fieldFocused)
                .disabled(waiting)
                .padding(.horizontal, 14)
                .frame(height: Theme.buttonHeight)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.fieldRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius).stroke(Theme.lineStrong, lineWidth: Theme.hairline))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Type the phrase")
        }
    }

    /// Counts down once a second while the app is active. Leaving the foreground restarts it.
    private func runCountdown() async {
        guard scenePhase == .active else {
            remaining = countdownSeconds
            return
        }
        while remaining > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            remaining -= 1
        }
        fieldFocused = true
    }
}

#Preview("Waiting") {
    FrictionGate(title: "Take 5 more minutes?", confirmLabel: "Add 5 min", countdownSeconds: 42,
                 phrase: "I am choosing this", onConfirm: {}, onCancel: {})
}

#Preview("Ready, dark") {
    FrictionGate(title: "Take 5 more minutes?", confirmLabel: "Add 5 min", countdownSeconds: 0,
                 phrase: "I am choosing this", onConfirm: {}, onCancel: {})
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    FrictionGate(title: "Take 5 more minutes?", confirmLabel: "Add 5 min", countdownSeconds: 0,
                 phrase: "I am choosing this", onConfirm: {}, onCancel: {})
        .dynamicTypeSize(.accessibility5)
}
