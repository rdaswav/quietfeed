import Foundation

enum ShieldAuthorization: Equatable {
    case notDetermined, approved, denied
}

enum ShieldError: Error, Equatable {
    case unavailable
}

/// Shields the official apps. `FamilyShieldController` is the real one; the fake backs the
/// simulator, previews and tests.
protocol ShieldController: AnyObject {
    var authorization: ShieldAuthorization { get }
    func requestAuthorization() async throws
    /// True when at least one app, category or site has been chosen.
    var hasSelection: Bool { get }
    /// Number of chosen items, used to tell whether a new choice loosens the old one.
    var selectionCount: Int { get }
    /// True when the shield is currently in force.
    var isShieldApplied: Bool { get }
    /// Shield the saved selection.
    func apply()
    func clear()
    /// Records whether the user wants the shield, where the monitor extension can see it, and
    /// starts or stops the daily re-shield schedule.
    func setEnabled(_ on: Bool)
    /// Unshield now and re-shield after `minutes`.
    func startPostMode(minutes: Int) throws
    var postModeEndsAt: Date? { get }
}

/// The self-healing rule, kept free of framework types so it can be tested against the fake.
enum ShieldReconciler {
    enum Outcome: Equatable {
        case none, applied, cleared
    }

    /// Called on every foreground.
    /// - Not approved: nothing to do.
    /// - Post Mode running: leave the shield alone.
    /// - Turned off but still shielding: clear it.
    /// - Turned on, apps chosen, shield empty: apply it again.
    @discardableResult
    static func reconcile(_ controller: ShieldController, enabled: Bool, now: Date = Date()) -> Outcome {
        guard controller.authorization == .approved else { return .none }
        if let ends = controller.postModeEndsAt, ends > now { return .none }
        if !enabled {
            guard controller.isShieldApplied else { return .none }
            controller.clear()
            return .cleared
        }
        guard controller.hasSelection, !controller.isShieldApplied else { return .none }
        controller.apply()
        return .applied
    }
}

final class FakeShieldController: ShieldController {
    var authorization: ShieldAuthorization
    var hasSelection: Bool
    var selectionCount: Int
    private(set) var isShieldApplied = false
    private(set) var postModeEndsAt: Date?
    /// What `requestAuthorization()` leads to.
    var nextAuthorization: ShieldAuthorization = .approved
    private let clock: () -> Date

    init(authorization: ShieldAuthorization = .notDetermined, selectionCount: Int = 0,
         clock: @escaping () -> Date = Date.init) {
        self.authorization = authorization
        self.selectionCount = selectionCount
        self.hasSelection = selectionCount > 0
        self.clock = clock
    }

    func requestAuthorization() async throws {
        authorization = nextAuthorization
    }

    private(set) var enabled = false
    func setEnabled(_ on: Bool) { enabled = on }

    func apply() { isShieldApplied = true }
    func clear() { isShieldApplied = false }

    func startPostMode(minutes: Int) throws {
        postModeEndsAt = clock().addingTimeInterval(TimeInterval(minutes * 60))
        isShieldApplied = false
    }

    /// Test helper: choose some items.
    func choose(_ count: Int) {
        selectionCount = count
        hasSelection = count > 0
    }
}
