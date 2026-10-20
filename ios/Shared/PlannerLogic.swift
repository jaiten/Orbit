import Foundation

enum PlannerLogic {
    /// Daily targets are fractional; weekly habits count a check-in on that day.
    /// Only habits scheduled for that day count, so a weekday habit never lowers a Saturday.
    /// Habits created later never lower an earlier day's score.
    static func dailyConsistency(habits: [Habit], logs: [HabitLog], on day: Date, calendar: Calendar = .current) -> Double {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
        let key = dayKey(day, calendar: calendar)
        let active = habits.filter { $0.createdAt < end && HabitRules.scheduledOn(rule: $0.frequencyRule, day: key) }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0.0) { result, habit in
            let count = logs.filter { $0.habitID == habit.id && $0.dayKey == key }.reduce(0) { $0 + $1.count }
            return result + min(1, Double(count) / Double(dailyTarget(habit)))
        } / Double(active.count)
    }
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func overlaps(_ start: Date, _ end: Date, _ otherStart: Date, _ otherEnd: Date) -> Bool { start < otherEnd && otherStart < end }
    static func consistencySeries(habits: [Habit], logs: [HabitLog], ending: Date, days: Int, calendar: Calendar = .current) -> [Double] {
        var counts: [String: [UUID: Int]] = [:]
        for log in logs { counts[log.dayKey, default: [:]][log.habitID, default: 0] += log.count }
        return (0..<max(0, days)).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: ending)!
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
            let key = dayKey(day, calendar: calendar)
            let active = habits.filter { $0.createdAt < end && HabitRules.scheduledOn(rule: $0.frequencyRule, day: key) }
            guard !active.isEmpty else { return 0 }
            let daily = counts[key] ?? [:]
            return active.reduce(0.0) { $0 + min(1, Double(daily[$1.id] ?? 0) / Double(dailyTarget($1))) } / Double(active.count)
        }
    }
    static func dailyProgress(_ habit: Habit, logs: [HabitLog], at date: Date, calendar: Calendar = .current) -> Int {
        counts(habit, logs: logs)[dayKey(date, calendar: calendar)] ?? 0
    }
    static func dailyTarget(_ habit: Habit) -> Int { HabitRules.dailyTarget(rule: habit.frequencyRule, target: habit.target) }
    /// Check-ins for one habit by local day key.
    static func counts(_ habit: Habit, logs: [HabitLog]) -> [String: Int] {
        logs.reduce(into: [:]) { result, log in if log.habitID == habit.id { result[log.dayKey, default: 0] += log.count } }
    }
    static func checkedToday(_ habit: Habit, logs: [HabitLog], at date: Date, calendar: Calendar = .current) -> Bool {
        HabitRules.checked(rule: habit.frequencyRule, target: habit.target, counts: counts(habit, logs: logs), day: dayKey(date, calendar: calendar))
    }
    /// Check-ins in the current period: the day, or the week for weekly habits.
    static func progress(_ habit: Habit, logs: [HabitLog], at date: Date, calendar: Calendar = .current) -> Int {
        HabitRules.periodProgress(rule: habit.frequencyRule, counts: counts(habit, logs: logs), day: dayKey(date, calendar: calendar), weekStart: HabitRules.weekStart(calendar))
    }
    static func isDue(_ habit: Habit, logs: [HabitLog], at date: Date, calendar: Calendar = .current) -> Bool {
        HabitRules.due(rule: habit.frequencyRule, target: habit.target, counts: counts(habit, logs: logs), day: dayKey(date, calendar: calendar), weekStart: HabitRules.weekStart(calendar))
    }
    /// "X of the last 7 days". Missed days are never counted against anything.
    static func checkedDays(_ habit: Habit, logs: [HabitLog], ending date: Date, days: Int = 7, calendar: Calendar = .current) -> Int {
        HabitRules.checkedDays(rule: habit.frequencyRule, target: habit.target, counts: counts(habit, logs: logs), day: dayKey(date, calendar: calendar), days: days)
    }
    /// For example "Weekdays · 1/1 today" or "2/3 this week".
    static func detail(_ habit: Habit, logs: [HabitLog], at date: Date) -> String {
        let schedule = HabitRules.schedule(habit.frequencyRule)
        let count = "\(progress(habit, logs: logs, at: date))/\(habit.target) \(schedule == "WEEKLY" ? "this week" : "today")"
        return schedule == "DAILY" || schedule == "WEEKLY" ? count : HabitRules.label(schedule) + " · " + count
    }
}

struct QuickAddResult {
    var title: String
    var date: Date?
    var hasTime: Bool
}

enum QuickAdd {
    /// Intentionally small English grammar: today/tomorrow and 6am / 6:30pm.
    static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current, plannedDay: Date? = nil) -> QuickAddResult {
        var title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var date: Date? = plannedDay
        var hasTime = false
        if let range = title.range(of: #"\b(today|tomorrow)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let offset = title[range].lowercased() == "tomorrow" ? 1 : 0
            date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
            title.removeSubrange(range)
        }
        let regex = try! NSRegularExpression(pattern: #"\b(1[0-2]|0?[1-9])(?::([0-5][0-9]))?\s*(am|pm)\b"#, options: .caseInsensitive)
        if let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           let hourRange = Range(match.range(at: 1), in: title),
           let meridiemRange = Range(match.range(at: 3), in: title),
           let fullRange = Range(match.range, in: title) {
            let hour = Int(title[hourRange])! % 12 + (title[meridiemRange].lowercased() == "pm" ? 12 : 0)
            let minute = Range(match.range(at: 2), in: title).flatMap { Int(title[$0]) } ?? 0
            let hadDate = date != nil
            date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date ?? now)
            if !hadDate, let scheduled = date, scheduled < now {
                date = calendar.date(byAdding: .day, value: 1, to: scheduled)
            }
            hasTime = true; title.removeSubrange(fullRange)
        }
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return QuickAddResult(title: title, date: date, hasTime: hasTime)
    }
}
