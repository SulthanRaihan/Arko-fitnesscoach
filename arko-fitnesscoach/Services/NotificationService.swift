import UserNotifications
import Foundation

// ════════════════════════════════════════════════════════════════════════════
// MARK: - NotificationService
// Manages local push notifications:
//   • Daily workout reminder (configurable time)
//   • Streak drop warning (if user hasn't worked out by evening)
//   • Post-workout celebration
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    private init() {
        Task { await refreshAuthStatus() }
    }

    // MARK: - Permission

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if granted { scheduleAll() }
        } catch { }
    }

    func refreshAuthStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule all recurring notifications

    func scheduleAll() {
        center.removeAllPendingNotificationRequests()
        scheduleDailyReminder(hour: 8, minute: 0)
        scheduleStreakWarning(hour: 19, minute: 30)
    }

    // MARK: - Daily workout reminder (default 08:00)

    func scheduleDailyReminder(hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Train 💪"
        content.body  = "Your body is ready. Open ARKO and crush today's workout!"
        content.sound = .default
        content.badge = 1

        var comps = DateComponents()
        comps.hour   = hour
        comps.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: "arko.daily.reminder",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - Streak warning (19:30 if no workout today)

    func scheduleStreakWarning(hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Don't break your streak! 🔥"
        content.body  = "You haven't worked out yet today. Even 15 minutes counts — let's go!"
        content.sound = .default

        var comps = DateComponents()
        comps.hour   = hour
        comps.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: "arko.streak.warning",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - Post-workout celebration (fire once, immediately)

    func sendWorkoutCompleteNotification(workoutName: String, calories: Int, streak: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Workout Complete! 🎉"
        content.body  = "\(workoutName) done — \(calories) kcal burned. Streak: \(streak) days 🔥"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("celebration.caf"))

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "arko.workout.complete.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - Milestone notifications

    func sendStreakMilestone(days: Int) {
        guard [3, 7, 14, 30].contains(days) else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(days)-Day Streak! 🏆"
        content.body  = "Incredible consistency — \(days) days in a row! Keep it up, champion."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "arko.streak.milestone.\(days)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - Cancel

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
