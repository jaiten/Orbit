import Foundation

/// Habit schedule rules on floating calendar days ("YYYY-MM-DD"), shared with Windows
/// (windows/ui/habits.js) and checked against shared/test-cases/habits.json.
/// Day arithmetic uses a UTC Gregorian calendar purely as a calendar, so daylight-saving
/// changes never shift a day.
enum HabitRules {
    static let schedules = ["DAILY", "WEEKDAYS", "WEEKENDS", "WEEKLY"]
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func addDays(_ key: String, _ days: Int) -> String {
        guard let date = date(key), let moved = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return self.key(moved)
    }
    /// 0 = Sunday … 6 = Saturday, matching JavaScript's Date#getDay.
    static func weekday(_ key: String) -> Int {
        date(key).map { calendar.component(.weekday, from: $0) - 1 } ?? 0
    }
    static func weekStartKey(_ key: String, weekStart: Int) -> String {
        addDays(key, -((weekday(key) - weekStart + 7) % 7))
    }
    /// The device's first weekday in the same numbering (0 = Sunday).
    static func weekStart(_ calendar: Calendar = .current) -> Int { calendar.firstWeekday - 1 }

    static func schedule(_ rule: String) -> String { schedules.contains(rule) ? rule : "DAILY" }
    static func label(_ rule: String) -> String {
        ["DAILY": "Daily", "WEEKDAYS": "Weekdays", "WEEKENDS": "Weekends", "WEEKLY": "Weekly"][schedule(rule)]!
    }
    static func dailyTarget(rule: String, target: Int) -> Int { schedule(rule) == "WEEKLY" ? 1 : max(1, target) }
    static func scheduledOn(rule: String, day: String) -> Bool {
        switch schedule(rule) {
        case "WEEKDAYS": return (1...5).contains(weekday(day))
        case "WEEKENDS": return [0, 6].contains(weekday(day))
        default: return true
        }
    }

    /// `counts` holds this habit's check-ins by day key.
    static func checked(rule: String, target: Int, counts: [String: Int], day: String) -> Bool {
        (counts[day] ?? 0) >= dailyTarget(rule: rule, target: target)
    }
    static func periodProgress(rule: String, counts: [String: Int], day: String, weekStart: Int) -> Int {
        guard schedule(rule) == "WEEKLY" else { return counts[day] ?? 0 }
        let start = weekStartKey(day, weekStart: weekStart), end = addDays(start, 7)
        return counts.filter { $0.key >= start && $0.key < end }.reduce(0) { $0 + $1.value }
    }
    /// Shown on days it is scheduled; a weekly habit stops asking once the week's target is met.
    static func due(rule: String, target: Int, counts: [String: Int], day: String, weekStart: Int) -> Bool {
        guard scheduledOn(rule: rule, day: day) else { return false }
        guard schedule(rule) == "WEEKLY" else { return true }
        return checked(rule: rule, target: target, counts: counts, day: day)
            || periodProgress(rule: rule, counts: counts, day: day, weekStart: weekStart) < max(1, target)
    }
    /// One habit's inputs for consistency: its schedule, the day it was created and its check-ins by day.
    struct Entry { var rule: String; var target: Int; var createdDay: String?; var counts: [String: Int] }
    /// Share of habits scheduled on `day` (and created by then) that were checked, with partial
    /// credit for daily targets; a weekly habit counts a check-in on that day. No habits gives 0.
    static func consistency(_ habits: [Entry], day: String) -> Double {
        let active = habits.filter { ($0.createdDay.map { $0 <= day } ?? true) && scheduledOn(rule: $0.rule, day: day) }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0.0) { $0 + min(1, Double($1.counts[day] ?? 0) / Double(dailyTarget(rule: $1.rule, target: $1.target))) } / Double(active.count)
    }
    /// Days checked in the `days` days ending with `day`. Missed days only lower the count.
    static func checkedDays(rule: String, target: Int, counts: [String: Int], day: String, days: Int = 7) -> Int {
        (0..<days).filter { checked(rule: rule, target: target, counts: counts, day: addDays(day, -$0)) }.count
    }
}
