import Foundation

enum PlannerLogic {
    /// Daily targets are fractional; weekly habits count a check-in on that day.
    /// Habits created later never lower an earlier day's score.
    static func dailyConsistency(habits: [Habit], logs: [HabitLog], on day: Date, calendar: Calendar = .current) -> Double {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
        let active = habits.filter { $0.createdAt < end }
        guard !active.isEmpty else { return 0 }
        let key = dayKey(day, calendar: calendar)
        return active.reduce(0.0) { result, habit in
            let count = logs.filter { $0.habitID == habit.id && $0.dayKey == key }.reduce(0) { $0 + $1.count }
            return result + min(1, Double(count) / Double(habit.frequencyRule == "WEEKLY" ? 1 : max(1, habit.target)))
        } / Double(active.count)
    }
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func overlaps(_ start: Date, _ end: Date, _ otherStart: Date, _ otherEnd: Date) -> Bool { start < otherEnd && otherStart < end }
    static func dailyProgress(_ habit: Habit, logs: [HabitLog], at date: Date, calendar: Calendar = .current) -> Int {
        logs.filter { $0.habitID == habit.id && $0.dayKey == dayKey(date, calendar: calendar) }.reduce(0) { $0 + $1.count }
    }
    static func dailyTarget(_ habit: Habit) -> Int { habit.frequencyRule == "WEEKLY" ? 1 : max(1, habit.target) }
    static func checkedToday(_ habit: Habit, logs: [HabitLog], at date: Date) -> Bool {
        dailyProgress(habit, logs: logs, at: date) >= dailyTarget(habit)
    }
    static func period(for habit: Habit, at date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: habit.frequencyRule == "WEEKLY" ? .weekOfYear : .day, for: date)!
    }

    static func progress(_ habit: Habit, logs: [HabitLog], at date: Date, calendar: Calendar = .current) -> Int {
        let interval = period(for: habit, at: date, calendar: calendar)
        let start = dayKey(interval.start, calendar: calendar)
        let end = dayKey(interval.end, calendar: calendar)
        return logs.filter { $0.habitID == habit.id && $0.dayKey >= start && $0.dayKey < end }
            .reduce(0) { $0 + $1.count }
    }

    /// An unfinished current period does not break yesterday's streak.
    static func streak(_ habit: Habit, logs: [HabitLog], at date: Date = .now, calendar: Calendar = .current) -> Int {
        let component: Calendar.Component = habit.frequencyRule == "WEEKLY" ? .weekOfYear : .day
        var cursor = date
        if progress(habit, logs: logs, at: cursor, calendar: calendar) < habit.target {
            cursor = calendar.date(byAdding: component, value: -1, to: cursor)!
        }
        var result = 0
        while period(for: habit, at: cursor, calendar: calendar).end > habit.createdAt,
              progress(habit, logs: logs, at: cursor, calendar: calendar) >= habit.target {
            result += 1
            cursor = calendar.date(byAdding: component, value: -1, to: cursor)!
        }
        return result
    }

    /// Prototype supports these explicit RRULEs. Unsupported rules are never guessed.
    static func nextOccurrence(after date: Date, rule: String, calendar: Calendar = .current) -> Date? {
        switch rule {
        case "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", "FREQ=WEEKLY;BYDAY=SA,SU":
            let weekdays = rule.hasSuffix("SA,SU") ? [1, 7] : [2, 3, 4, 5, 6]
            for offset in 1...7 {
                if let next = calendar.date(byAdding: .day, value: offset, to: date), weekdays.contains(calendar.component(.weekday, from: next)) { return next }
            }
            return nil
        case "FREQ=DAILY": return calendar.date(byAdding: .day, value: 1, to: date)
        case "FREQ=WEEKLY": return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case "FREQ=MONTHLY": return calendar.date(byAdding: .month, value: 1, to: date)
        default: return nil
        }
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
