import Foundation
import DeviceActivity

/// Re-shields the official apps when Post Mode ends and at the start and end of each day.
/// All the logic lives in `ShieldShared`, which is compiled into the app as well.
final class QuietFeedMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == .daily { ShieldShared.reapplyIfDue() }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Post Mode's end time has passed by now, so reapplyIfDue clears it and shields again.
        ShieldShared.reapplyIfDue(now: Date().addingTimeInterval(1))
    }
}
