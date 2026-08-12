import UIKit
import UserNotifications

@MainActor
enum SamoyedSystemSurfaceDormancy {
    private static let migrationKey = "Samoyed.v1.SystemSurfacesDormant"

    static func apply(defaults: UserDefaults = .standard) {
        // Keep the quick-action list empty on every launch; older OS snapshots can linger.
        UIApplication.shared.shortcutItems = []

        guard !defaults.bool(forKey: migrationKey) else { return }
        defaults.set(true, forKey: migrationKey)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        Task {
            guard #available(iOS 16.1, *) else { return }
            await SamoyedCurrentBlockLiveActivityController.endAll()
        }
    }
}
