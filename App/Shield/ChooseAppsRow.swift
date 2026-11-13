#if canImport(FamilyControls)
import SwiftUI
import FamilyControls

/// Opens the system app picker. Adding apps applies at once; removing any goes through the gate.
struct ChooseAppsRow: View {
    let controller: FamilyShieldController
    let version: Int
    /// Runs after a new choice has been saved.
    let onCommitted: () -> Void
    /// Asks the screen to show the friction gate, then run `action`.
    let requestGate: (_ title: String, _ action: @escaping () -> Void) -> Void

    @State private var presented = false
    @State private var draft = FamilyActivitySelection()

    var body: some View {
        Button {
            draft = controller.selection
            presented = true
        } label: {
            HStack {
                Text("Choose apps").font(Theme.bodyFont).foregroundStyle(Theme.accent)
                Spacer()
                Text(summary).font(Theme.bodyFont).foregroundStyle(Theme.textMuted)
            }
        }
        .familyActivityPicker(isPresented: $presented, selection: $draft)
        .onChange(of: presented) { _, isOpen in
            if !isOpen { finish() }
        }
        .listRowBackground(Theme.surface)
    }

    private var summary: String {
        _ = version
        let n = controller.selectionCount
        return n == 0 ? "None" : "\(n) chosen"
    }

    private func finish() {
        let chosen = draft
        guard chosen != controller.selection else { return }
        if chosen.itemCount >= controller.selectionCount {
            controller.commit(chosen)
            onCommitted()
        } else {
            requestGate("Take apps off the shield") {
                controller.commit(chosen)
                onCommitted()
            }
        }
    }
}
#endif
