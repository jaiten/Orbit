import Foundation

enum PlannerLogic {
    /// Today's planner day, which begins at the day start (DayStart), not midnight.
    static var today: String { dayKey(DayStart.shifted(.now)) }
    /// Midnight at the start of today's planner day, for views that work with dates.
    static var todayDate: Date { Calendar.current.startOfDay(for: DayStart.shifted(.now)) }
    /// The planner day a moment (a completion, a check-in, a habit's creation) counts for.
    static func plannerDay(_ date: Date) -> String { dayKey(DayStart.shifted(date)) }
    /// Daily targets are fractional; weekly habits count a check-in on that day.
    /// Only habits scheduled for that day count, and habits created later never lower an earlier day.
    static func dailyConsistency(habits: [Habit], logs: [HabitLog], on day: Date, calendar: Calendar = .current) -> Double {
        HabitRules.consistency(entries(habits, logs: logs, calendar: calendar), day: dayKey(day, calendar: calendar))
    }
    static func entries(_ habits: [Habit], logs: [HabitLog], calendar: Calendar = .current) -> [HabitRules.Entry] {
        var counts: [UUID: [String: Int]] = [:]
        for log in logs { counts[log.habitID, default: [:]][log.dayKey, default: 0] += log.count }
        return habits.map { HabitRules.Entry(rule: $0.frequencyRule, target: $0.target, createdDay: dayKey(DayStart.shifted($0.createdAt), calendar: calendar), counts: counts[$0.id] ?? [:]) }
    }
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func overlaps(_ start: Date, _ end: Date, _ otherStart: Date, _ otherEnd: Date) -> Bool { start < otherEnd && otherStart < end }
    static func consistencySeries(habits: [Habit], logs: [HabitLog], ending: Date, days: Int, calendar: Calendar = .current, tasks: [PlannerTask] = [], includeTasks: Bool = true) -> [Double] {
        let inputs = entries(habits, logs: logs, calendar: calendar)
        // Each task is filed under its day once (the day it was finished, else its date), rather than
        // being looked at again for every day shown.
        var planned: [String: Int] = [:], finished: [String: Int] = [:]
        if includeTasks {
            for task in tasks where !task.note {
                guard let key = task.completedAt.map({ dayKey(DayStart.shifted($0), calendar: calendar) }) ?? task.day else { continue }
                planned[key, default: 0] += 1
                if task.completedAt != nil { finished[key, default: 0] += 1 }
            }
        }
        return (0..<max(0, days)).reversed().map { offset in
            let key = dayKey(calendar.date(byAdding: .day, value: -offset, to: ending)!, calendar: calendar)
            let active = inputs.filter { ($0.createdDay.map { $0 <= key } ?? true) && HabitRules.scheduledOn(rule: $0.rule, day: key) }
            let habitDone = active.reduce(0.0) { sum, entry in
                sum + min(1, Double(entry.counts[key] ?? 0) / Double(HabitRules.dailyTarget(rule: entry.rule, target: entry.target)))
            }
            let total = active.count + (planned[key] ?? 0)
            return total == 0 ? 0 : (habitDone + Double(finished[key] ?? 0)) / Double(total)
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
    /// Every habit's check-ins by day, read from the logs once. Screens with many rows use this
    /// instead of scanning all the logs again for each row.
    static func countsByHabit(_ logs: [HabitLog]) -> [UUID: [String: Int]] {
        var result: [UUID: [String: Int]] = [:]
        for log in logs { result[log.habitID, default: [:]][log.dayKey, default: 0] += log.count }
        return result
    }
    static func checkedToday(_ habit: Habit, logs: [HabitLog], at date: Date, calendar: Calendar = .current) -> Bool {
        checkedToday(habit, counts: counts(habit, logs: logs), at: date, calendar: calendar)
    }
    static func checkedToday(_ habit: Habit, counts: [String: Int], at date: Date, calendar: Calendar = .current) -> Bool {
        HabitRules.checked(rule: habit.frequencyRule, target: habit.target, counts: counts, day: dayKey(date, calendar: calendar))
    }
    /// Check-ins in the current period: the day, or the week for weekly habits.
    static func progress(_ habit: Habit, logs: [HabitLog], at date: Date, calendar: Calendar = .current) -> Int {
        progress(habit, counts: counts(habit, logs: logs), at: date, calendar: calendar)
    }
    static func progress(_ habit: Habit, counts: [String: Int], at date: Date, calendar: Calendar = .current) -> Int {
        HabitRules.periodProgress(rule: habit.frequencyRule, counts: counts, day: dayKey(date, calendar: calendar), weekStart: HabitRules.weekStart(calendar))
    }
    static func isDue(_ habit: Habit, logs: [HabitLog], at date: Date, calendar: Calendar = .current) -> Bool {
        isDue(habit, counts: counts(habit, logs: logs), at: date, calendar: calendar)
    }
    static func isDue(_ habit: Habit, counts: [String: Int], at date: Date, calendar: Calendar = .current) -> Bool {
        HabitRules.due(rule: habit.frequencyRule, target: habit.target, counts: counts, day: dayKey(date, calendar: calendar), weekStart: HabitRules.weekStart(calendar))
    }
    /// "X of the last 7 days". Missed days are never counted against anything.
    static func checkedDays(_ habit: Habit, logs: [HabitLog], ending date: Date, days: Int = 7, calendar: Calendar = .current) -> Int {
        HabitRules.checkedDays(rule: habit.frequencyRule, target: habit.target, counts: counts(habit, logs: logs), day: dayKey(date, calendar: calendar), days: days)
    }
    /// For example "Weekdays · 1 of 1 today" or "2 of 3 this week", as on Windows.
    static func detail(_ habit: Habit, logs: [HabitLog], at date: Date) -> String {
        detail(habit, counts: counts(habit, logs: logs), at: date)
    }
    static func detail(_ habit: Habit, counts: [String: Int], at date: Date) -> String {
        let schedule = HabitRules.schedule(habit.frequencyRule)
        let unit = HabitRules.period(schedule)
        let count = "\(progress(habit, counts: counts, at: date)) of \(habit.target) \(unit.map { "this " + $0 } ?? "today")"
        return schedule == "DAILY" || unit != nil ? count : HabitRules.label(schedule) + " · " + count
    }
}
