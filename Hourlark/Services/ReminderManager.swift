import Foundation
import UserNotifications

/// Local reminders only. They're scheduled on this iPhone and never involve a server.
enum ReminderManager {
    enum Keys {
        static let dailyOn = "reminder.daily.enabled"
        static let dailyMinutes = "reminder.daily.minutes"
        static let dailyDays = "reminder.daily.days"
        static let longOn = "reminder.long.enabled"
        static let longHours = "reminder.long.hours"
    }

    private static let center = UNUserNotificationCenter.current()

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// `dayMask` bit 0 = Sunday … bit 6 = Saturday.
    static func applyDaily(enabled: Bool, minutes: Int, dayMask: Int) {
        center.removePendingNotificationRequests(withIdentifiers: (1...7).map { "daily-\($0)" })
        guard enabled else { return }
        for weekday in 1...7 where dayMask & (1 << (weekday - 1)) != 0 {
            var when = DateComponents()
            when.weekday = weekday
            when.hour = minutes / 60
            when.minute = minutes % 60
            let content = UNMutableNotificationContent()
            content.title = "Log your hours"
            content.body = "Did you volunteer or work today? Start the timer or add time in Hourlark."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            center.add(UNNotificationRequest(identifier: "daily-\(weekday)", content: content, trigger: trigger))
        }
    }

    /// "Still tracking?" nudge after the timer has run for a while.
    static func scheduleLongTimerIfEnabled(causeName: String) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Keys.longOn) else { return }
        let hours = max(1, defaults.integer(forKey: Keys.longHours) == 0 ? 4 : defaults.integer(forKey: Keys.longHours))
        let content = UNMutableNotificationContent()
        content.title = "Still tracking \(causeName)?"
        content.body = "Your timer has been running for \(hours) hours. Stop it if you're done."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3600), repeats: false)
        center.add(UNNotificationRequest(identifier: "timer-long", content: content, trigger: trigger))
    }

    static func cancelLongTimer() {
        center.removePendingNotificationRequests(withIdentifiers: ["timer-long"])
    }
}

/// Lets reminders show as banners even while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
