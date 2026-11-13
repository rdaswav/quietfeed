#if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

// This one file is compiled into both the app and the monitor extension, so the shield is
// applied by the same code whichever process does it.

extension ManagedSettingsStore.Name {
    static let quietFeed = ManagedSettingsStore.Name("quietFeed")
}

extension DeviceActivityName {
    static let postMode = DeviceActivityName("quietFeed.postMode")
    static let daily = DeviceActivityName("quietFeed.daily")
}

extension FamilyActivitySelection {
    var itemCount: Int { applicationTokens.count + categoryTokens.count + webDomainTokens.count }
}

enum ShieldShared {
    static let groupID = "group.dev.quietfeed.app"
    /// DeviceActivity accepts nothing shorter than this.
    static let minimumPostModeMinutes = 15

    private static let enabledKey = "shield.enabled"
    private static let postModeKey = "postMode.endsAt"

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    private static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var selectionURL: URL { containerURL.appendingPathComponent("shield-selection.plist") }

    static func loadSelection() -> FamilyActivitySelection {
        guard let data = try? Data(contentsOf: selectionURL),
              let saved = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return saved
    }

    static func saveSelection(_ selection: FamilyActivitySelection) {
        if let data = try? PropertyListEncoder().encode(selection) {
            try? data.write(to: selectionURL, options: .atomic)
        }
    }

    static var enabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static var postModeEndsAt: Date? {
        get { defaults.object(forKey: postModeKey) as? Date }
        set {
            if let newValue { defaults.set(newValue, forKey: postModeKey) } else { defaults.removeObject(forKey: postModeKey) }
        }
    }

    static var store: ManagedSettingsStore { ManagedSettingsStore(named: .quietFeed) }

    static var isShieldApplied: Bool {
        let s = store.shield
        return s.applications != nil || s.applicationCategories != nil || s.webDomains != nil
    }

    static func applyShield(_ selection: FamilyActivitySelection) {
        let s = store
        s.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        s.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        s.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    static func clearShield() {
        store.clearAllSettings()
    }

    /// Re-shields when the user wants it, apps are chosen and Post Mode is not running.
    /// The extension calls this when an interval starts or ends.
    static func reapplyIfDue(now: Date = Date()) {
        if let ends = postModeEndsAt, ends > now { return }
        postModeEndsAt = nil
        guard enabled else { return }
        let selection = loadSelection()
        guard selection.itemCount > 0 else { return }
        applyShield(selection)
    }
}
#endif
