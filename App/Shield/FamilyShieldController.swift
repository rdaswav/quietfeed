#if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

/// The real shield. Needs the Family Controls entitlement and a real device.
final class FamilyShieldController: ShieldController {
    private(set) var selection: FamilyActivitySelection

    init() {
        selection = ShieldShared.loadSelection()
        if ShieldShared.enabled { scheduleDaily() }
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
    var isShieldApplied: Bool { ShieldShared.isShieldApplied }

    /// Saves a new choice where the monitor extension can read it, and updates the shield if it is on.
    func commit(_ new: FamilyActivitySelection) {
        selection = new
        ShieldShared.saveSelection(new)
        if isShieldApplied { apply() }
    }

    func apply() { ShieldShared.applyShield(selection) }

    func clear() { ShieldShared.clearShield() }

    func setEnabled(_ on: Bool) {
        ShieldShared.enabled = on
        if on {
            scheduleDaily()
        } else {
            DeviceActivityCenter().stopMonitoring([.daily, .postMode])
            ShieldShared.postModeEndsAt = nil
        }
    }

    var postModeEndsAt: Date? { ShieldShared.postModeEndsAt }

    /// Schedules the re-shield first. Only if that works is the shield lifted, so a failure leaves it up.
    func startPostMode(minutes: Int) throws {
        let length = max(minutes, ShieldShared.minimumPostModeMinutes)
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(length * 60))
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: Calendar.current.dateComponents(parts, from: now),
            intervalEnd: Calendar.current.dateComponents(parts, from: end),
            repeats: false)
        try DeviceActivityCenter().startMonitoring(.postMode, during: schedule)
        ShieldShared.postModeEndsAt = end
        clear()
    }

    /// Re-applies the shield every day at 04:00 even if the app was never opened.
    private func scheduleDaily() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 4, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true)
        try? DeviceActivityCenter().startMonitoring(.daily, during: schedule)
    }
}
#endif
