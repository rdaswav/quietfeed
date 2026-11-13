#if canImport(FamilyControls) && canImport(ManagedSettings)
import Foundation
import FamilyControls
import ManagedSettings

extension ManagedSettingsStore.Name {
    static let quietFeed = ManagedSettingsStore.Name("quietFeed")
}

enum ShieldGroup {
    static let id = "group.dev.quietfeed.app"
}

extension FamilyActivitySelection {
    var itemCount: Int { applicationTokens.count + categoryTokens.count + webDomainTokens.count }
}

/// The real shield. Needs the Family Controls entitlement and a real device.
/// Post Mode scheduling (DeviceActivity) arrives with the monitor extension in T19.
final class FamilyShieldController: ShieldController {
    private(set) var selection: FamilyActivitySelection
    private let store = ManagedSettingsStore(named: .quietFeed)
    private let selectionURL: URL
    private let defaults: UserDefaults

    init() {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ShieldGroup.id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        selectionURL = base.appendingPathComponent("shield-selection.plist")
        defaults = UserDefaults(suiteName: ShieldGroup.id) ?? .standard
        if let data = try? Data(contentsOf: selectionURL),
           let saved = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        } else {
            selection = FamilyActivitySelection()
        }
    }

    var authorization: ShieldAuthorization {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: return .approved
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    var hasSelection: Bool { selection.itemCount > 0 }
    var selectionCount: Int { selection.itemCount }

    var isShieldApplied: Bool {
        store.shield.applications != nil
            || store.shield.applicationCategories != nil
            || store.shield.webDomains != nil
    }

    /// Saves a new choice where the monitor extension can read it, and updates the shield if it is on.
    func commit(_ new: FamilyActivitySelection) {
        selection = new
        if let data = try? PropertyListEncoder().encode(new) {
            try? data.write(to: selectionURL, options: .atomic)
        }
        if isShieldApplied { apply() }
    }

    func apply() {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    func clear() {
        store.clearAllSettings()
    }

    func startPostMode(minutes: Int) throws {
        throw ShieldError.unavailable
    }

    var postModeEndsAt: Date? {
        defaults.object(forKey: "postMode.endsAt") as? Date
    }
}
#endif
