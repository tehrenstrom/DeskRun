import Foundation
import Observation
import UserNotifications

@Observable
class DeskRunNotificationManager {
    private let workoutStore: WorkoutStore
    private let goalManager: GoalManager
    private let statsCalculator: StatsCalculator
    private var settings: AppSettings

    var permissionGranted: Bool = false
    private var notificationsSentToday: Int = 0
    private var lastNotificationDate: Date?

    init(workoutStore: WorkoutStore, goalManager: GoalManager, statsCalculator: StatsCalculator, settings: AppSettings) {
        self.workoutStore = workoutStore
        self.goalManager = goalManager
        self.statsCalculator = statsCalculator
        self.settings = settings
    }

    // MARK: - Setup

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
                if granted {
                    self?.scheduleRecurringChecks()
                }
            }
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        if settings.notificationsEnabled {
            scheduleRecurringChecks()
        } else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
    }

    // MARK: - Scheduling

    func scheduleRecurringChecks() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        guard settings.notificationsEnabled else { return }

        if settings.morningMotivation {
            scheduleMorningMotivation()
        }
        if settings.goalNudges {
            scheduleAfternoonNudge()
        }
        if settings.streakAlerts {
            scheduleEveningStreakCheck()
        }
    }

    // MARK: - Morning Motivation (8 AM)

    private func scheduleMorningMotivation() {
        var dateComponents = DateComponents()
        dateComponents.hour = max(settings.quietHoursEnd, 8)
        dateComponents.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Good morning! ☀️"
        content.sound = .default

        // Build body based on current state
        let streak = statsCalculator.currentStreak
        if let journey = goalManager.activeGoals.first(where: { $0.timeframe == .custom }) {
            let prog = goalManager.progress(for: journey, workouts: workoutStore.workouts, settings: settings)
            content.body = "Day \(streak + 1) of your \(journey.name) journey — \(prog.formattedCurrent) \(journey.unit.symbol) down. A morning walk would be a great start."
        } else if streak > 0 {
            content.body = "You're on a \(streak)-day streak! Keep it going with a morning walk."
        } else {
            content.body = "Start your day with a walk — your treadmill is ready."
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "morning-motivation", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Afternoon Goal Nudge (2 PM)

    private func scheduleAfternoonNudge() {
        var dateComponents = DateComponents()
        dateComponents.hour = 14
        dateComponents.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Afternoon check-in"
        content.sound = .default

        let today = statsCalculator.todayStats
        if today.workoutCount == 0 {
            content.body = "You haven't walked yet today. A quick 15-minute walk might help beat the afternoon slump."
        } else if let goal = goalManager.activeGoals.first(where: { $0.timeframe == .daily }) {
            let prog = goalManager.progress(for: goal, workouts: workoutStore.todaysWorkouts, settings: settings)
            if prog.percentage < 1.0 {
                content.body = "\(prog.formattedCurrent) / \(prog.formattedTarget) \(goal.unit.symbol) today. A short walk would get you closer."
            } else {
                content.body = "You've already hit today's goal! 🎉 Bonus miles are always welcome though."
            }
        } else {
            content.body = "Afternoon slump? A 15-minute walk might help. Your treadmill is right there."
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "afternoon-nudge", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Evening Streak Check (7 PM)

    private func scheduleEveningStreakCheck() {
        var dateComponents = DateComponents()
        dateComponents.hour = 19
        dateComponents.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Streak check"
        content.sound = .default

        let streak = statsCalculator.currentStreak
        let today = statsCalculator.todayStats
        if today.workoutCount == 0 && streak > 0 {
            content.body = "Don't break your \(streak)-day streak! You haven't walked yet today."
        } else if today.workoutCount == 0 {
            content.body = "There's still time for a quick evening walk before bed."
        } else {
            content.body = "Great work today! \(settings.distanceString(today.distance)) walked."
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "evening-streak", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Instant Notifications (call these directly)

    func sendMilestoneNotification(title: String, body: String) {
        guard settings.notificationsEnabled && settings.milestoneAlerts else { return }
        guard canSendNotification() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "milestone-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
        recordNotificationSent()
    }

    func sendWeeklySummary() {
        guard settings.notificationsEnabled && settings.weeklySummary else { return }

        let weekStats = statsCalculator.stats(for: .week)
        let content = UNMutableNotificationContent()
        content.title = "Weekly Summary 📊"
        content.body = "This week: \(settings.distanceString(weekStats.distance)), \(weekStats.formattedDuration) walking, \(weekStats.steps) steps."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "weekly-summary",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Rate Limiting

    private func canSendNotification() -> Bool {
        let calendar = Calendar.current
        if let lastDate = lastNotificationDate, calendar.isDateInToday(lastDate) {
            return notificationsSentToday < settings.maxNotificationsPerDay
        }
        // New day — reset counter
        notificationsSentToday = 0
        return true
    }

    private func recordNotificationSent() {
        let calendar = Calendar.current
        if let lastDate = lastNotificationDate, !calendar.isDateInToday(lastDate) {
            notificationsSentToday = 0
        }
        notificationsSentToday += 1
        lastNotificationDate = Date()
    }

    private func isQuietHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        if settings.quietHoursStart > settings.quietHoursEnd {
            // Wraps midnight (e.g., 22-8)
            return hour >= settings.quietHoursStart || hour < settings.quietHoursEnd
        }
        return hour >= settings.quietHoursStart && hour < settings.quietHoursEnd
    }
}
