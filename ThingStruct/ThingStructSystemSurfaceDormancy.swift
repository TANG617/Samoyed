import UIKit
import UserNotifications

@MainActor
enum ThingStructSystemSurfaceDormancy {
    private static let migrationKey = "ThingStruct.v0.3.SystemSurfacesDormant"

    static func apply(defaults: UserDefaults = .standard) {
        // Keep the quick-action list empty on every launch; older OS snapshots can linger.
        UIApplication.shared.shortcutItems = []

        guard !defaults.bool(forKey: migrationKey) else { return }
        defaults.set(true, forKey: migrationKey)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        Task {
            guard #available(iOS 16.1, *) else { return }
            await ThingStructCurrentBlockLiveActivityController.endAll()
        }
    }
}
