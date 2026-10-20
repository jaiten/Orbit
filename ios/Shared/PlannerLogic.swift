import Foundation

enum PlannerLogic {
    /// Daily targets are fractional; weekly habits count a check-in on that day.
    /// Only habits scheduled for that day count, and habits created later never lower an earlier day.
    static func dailyConsistency(habits: [Habit], logs: [HabitLog], on day: Date, calendar: Calendar = .current) -> Double {
        HabitRules.consistency(entries(habits, logs: logs, calendar: calendar), day: dayKey(day, calendar: calendar))
    }
    static func entries(_ habits: [Habit], logs: [HabitLog], calendar: Calendar = .current) -> [HabitRules.Entry] {
        var counts: [UUID: [String: Int]] = [:]
        for log in logs { counts[log.habitID, default: [:]][log.dayKey, default: 0] += log.count }
        return habits.map { HabitRules.Entry(rule: $0.frequencyRule, target: $0.target, createdDay: dayKey($0.createdAt, calendar: calendar), counts: counts[$0.id] ?? [:]) }
    }
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func overlaps(_ start: Date, _ end: Date, _ otherStart: Date, _ otherEnd: Date) -> Bool { start < otherEnd && otherStart < end }
    static func consistencySeries(habits: [Habit], logs: [HabitLog], ending: Date, days: Int, calendar: Calendar = .current) -> [Double] {
        let inputs = entries(habits, logs: logs, calendar: calendar)
        return (0..<max(0, days)).reversed().map { offset in
            HabitRules.consistency(inputs, day: dayKey(calendar.date(byAdding: .day, value: -offset, to: ending)!, calendar: calendar))
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
