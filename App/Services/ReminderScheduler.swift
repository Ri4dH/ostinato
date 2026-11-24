import Foundation
import PracticeKit
import UserNotifications

/// Daily practice reminders and the "Still practicing?" nudge.
///
/// Reminders are scheduled one per day for the next week (not repeating), so
/// today's can be removed once the goal is met. Max one per day.
@MainActor
final class ReminderScheduler {
    private let center = UNUserNotificationCenter.current()
    private static let reminderPrefix = "reminder."
    private static let longSessionID = "long-session"

    /// Asks permission. Only called when the user turns reminders on.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func reschedule(settings: AppSettings, todayMinutes: Int, now: Date = Date()) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) })
        guard settings.reminderEnabled else { return }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let calendar = Calendar.current
        let goalMetToday = todayMinutes >= settings.goal.dailyMinutes
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            if offset == 0, goalMetToday { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = settings.reminderDateComponents.hour
            components.minute = settings.reminderDateComponents.minute
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Time to practice")
            content.body = Self.gentleMessages[offset % Self.gentleMessages.count]
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Self.reminderPrefix + "\(offset)-\(components.day ?? 0)",
                                                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Schedules "Still practicing?" for when active time reaches 4 hours.
    func updateLongSessionNudge(for session: ActiveSession?, now: Date = Date()) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.longSessionID])
        guard let session, !session.isPaused else { return }
        let remaining = SessionEngine.longSessionThreshold - session.elapsed(at: now)
        guard remaining > 0 else { return }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Still practicing?")
        content.body = String(localized: "Your session has been running for 4 hours. Open Ostinato to finish or keep going.")
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.longSessionID, content: content, trigger: trigger))
    }

    private static let gentleMessages: [String] = [
        String(localized: "A few minutes today keeps things moving."),
        String(localized: "Your instrument is ready when you are."),
        String(localized: "Pick one passage and give it ten minutes."),
        String(localized: "Short sessions count too.")
    ]
}
