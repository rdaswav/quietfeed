import SwiftUI
import QuietFeedCore

/// The one gate for every loosening action: a countdown, then a typed phrase.
struct FrictionGate: View {
    let title: String
    let countdownSeconds: Int
    let phrase: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var remaining: Int
    @State private var typed = ""
    @Environment(\.scenePhase) private var scenePhase

    init(title: String, countdownSeconds: Int, phrase: String,
         onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.countdownSeconds = countdownSeconds
        self.phrase = phrase
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _remaining = State(initialValue: countdownSeconds)
    }

    private var phraseMatches: Bool {
        FrictionPolicy.phraseMatches(typed: typed, phrase: phrase)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if remaining > 0 {
                countdownStage
            } else {
                phraseStage
            }
            Button("Cancel", action: onCancel)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 4)
        }
        .padding(Theme.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task(id: scenePhase) { await runCountdown() }
    }

    private var countdownStage: some View {
        VStack(spacing: 12) {
            Text("Wait")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)
            Text(TimeText.clock(remaining))
                .font(Font.largeTitle.monospacedDigit())
                .foregroundStyle(Theme.text)
                .accessibilityLabel("\(remaining) seconds left")
            Text("Leaving the app restarts the timer.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var phraseStage: some View {
        VStack(spacing: 12) {
            Text("Type to continue:")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
            Text("\u{201C}\(phrase)\u{201D}")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            TextField("", text: $typed)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.line, lineWidth: Theme.hairline))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Type the phrase")
            Button(action: onConfirm) {
                Text("Continue")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accent.opacity(phraseMatches ? 1 : 0.4),
                                in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            }
            .disabled(!phraseMatches)
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
    }
}

#Preview("Countdown") {
    FrictionGate(title: "Add 5 minutes to Instagram", countdownSeconds: 27, phrase: "I am choosing to scroll",
                 onConfirm: {}, onCancel: {})
}

#Preview("Phrase") {
    FrictionGate(title: "Add 5 minutes to Instagram", countdownSeconds: 0, phrase: "I am choosing to scroll",
                 onConfirm: {}, onCancel: {})
        .preferredColorScheme(.dark)
}
