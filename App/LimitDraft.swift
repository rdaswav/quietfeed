import QuietFeedCore

/// Settings edits that loosen a limit wait here and are applied together, behind one friction gate.
/// Without this, every tap of a stepper that loosens something (shortening the countdown, raising a
/// budget) opened its own gate with its own countdown. Edits that only tighten still apply at once.
struct LimitDraft: Equatable {
    private(set) var pending: LimitSettings?

    var hasPending: Bool { pending != nil }

    /// What the screen should show: the waiting values if there are any, otherwise what is saved.
    func working(from saved: LimitSettings) -> LimitSettings { pending ?? saved }

    /// How many separate loosenings are waiting, for the banner.
    func waitingCount(from saved: LimitSettings) -> Int {
        guard let pending else { return 0 }
        return FrictionPolicy.loosenings(from: saved, to: pending).filter(FrictionPolicy.needsGate).count
    }

    /// Applies `change` on top of any waiting edits. If the result still loosens something it keeps waiting,
    /// otherwise it is saved at once (which also happens when the edits are undone back to what is saved).
    mutating func edit(_ change: (inout LimitSettings) -> Void, model: AppModel) {
        var new = pending ?? model.limits
        change(&new)
        switch model.proposeLimits(new) {
        case .needsGate: pending = new
        case .applied, .unchanged: pending = nil
        }
    }

    /// Called after the gate has been passed.
    mutating func applyPending(to model: AppModel) {
        guard let pending else { return }
        model.commitLimits(pending)
        self.pending = nil
    }

    mutating func discard() { pending = nil }
}
