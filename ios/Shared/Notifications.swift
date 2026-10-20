import Foundation
import UserNotifications
import SwiftData

actor NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    struct Reminder: Sendable {
        let id: String
        let title: String
        let body: String
        let date: Date
    }

    /// iOS limits pending requests; keep the nearest 60 and refill on every foreground/edit.
    /// Storage has no reminder cap. Only Orbit-owned pending notifications are replaced.
    func replace(with reminders: [Reminder]) async throws {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("orbit.") }.map(\.identifier))
        for reminder in reminders.filter({ $0.date > .now }).sorted(by: { $0.date < $1.date }).prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title; content.body = reminder.body; content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
            try await center.add(UNNotificationRequest(identifier: reminder.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }

    @MainActor static func reminders(context: ModelContext, now: Date = .now) throws -> [Reminder] {
        let tasks = try context.fetch(FetchDescriptor<PlannerTask>())
        let habits = try context.fetch(FetchDescriptor<Habit>())
        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        var result = tasks.filter { $0.completedAt == nil }.flatMap { task in
            task.reminders.enumerated().map { index, date in
                Reminder(id: "orbit.task.\(task.id).\(index)", title: task.title, body: "Reminder", date: date)
            }
        }
        for habit in habits {
            for offset in 0..<7 {
                let day = Calendar.current.date(byAdding: .day, value: offset, to: now)!
                if PlannerLogic.checkedToday(habit, logs: logs, at: day) { continue }
                for (kind, minutes) in [("reminder", habit.reminderMinutes), ("nudge", habit.nudgeMinutes)] {
                    guard let minutes, let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) else { continue }
                    result.append(Reminder(id: "orbit.habit.\(habit.id).\(offset).\(kind)", title: habit.title,
                        body: kind == "nudge" ? "Not checked yet today." : "Habit reminder", date: date))
                }
            }
        }
        if UserDefaults.standard.bool(forKey: "generalCheckIn") {
            let minutes = UserDefaults.standard.object(forKey: "checkInMinutes") as? Int ?? 1080
            for offset in 0..<7 {
                let day = Calendar.current.date(byAdding: .day, value: offset, to: now)!
                if let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) {
                    result.append(Reminder(id: "orbit.checkin.\(offset)", title: "Daily check-in", body: "Take a minute to plan your day.", date: date))
                }
            }
        }
        return result
    }
}
