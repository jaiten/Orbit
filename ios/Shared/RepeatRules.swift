import Foundation

/// Recurring tasks: a task with a repeat rule ("daily", "weekdays", "weekly", "monthly", "yearly") and
/// `repeatEvery` (2 for every two weeks) makes its next copy when it is ticked off. The planned day and the
/// due date both move forward by the rule, past the day it was finished, so missed ones never pile up.
/// The copy's ID comes from the task's ID and its new day, so two devices finishing the same task offline
/// make the same record. Mirrors windows/ui/repeats.js; cases in shared/test-cases/repeats.json.
/// (Older versions' `recurrenceRule` is separate: those tasks were turned into habits.)
enum RepeatRules {
    static let rules = ["daily", "weekdays", "weekly", "monthly", "yearly"]
    /// The editor's choices: (value "rule:every", label).
    static let choices: [(value: String, label: String)] = [
        ("", "Never"), ("daily:1", "Every day"), ("weekdays:1", "Every weekday"), ("weekly:1", "Every week"),
        ("weekly:2", "Every 2 weeks"), ("monthly:1", "Every month"), ("yearly:1", "Every year"),
    ]
    static func valid(_ rule: String?) -> Bool { rule.map(rules.contains) ?? false }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private static func parts(_ key: String) -> (Int, Int, Int)? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? (p[0], p[1], p[2]) : nil
    }
    private static func format(_ y: Int, _ m: Int, _ d: Int) -> String { String(format: "%04d-%02d-%02d", y, m, d) }
    /// Months later, kept inside the month (January 31 + 1 month = February 28).
    static func addMonths(_ key: String, _ months: Int) -> String {
        guard let (y, m, d) = parts(key) else { return key }
        let total = y * 12 + (m - 1) + months
        let year = Int((Double(total) / 12).rounded(.down)), month = total - year * 12 + 1
        let first = utc.date(from: DateComponents(year: year, month: month, day: 1))!
        let length = utc.range(of: .day, in: .month, for: first)!.count
        return format(year, month, min(d, length))
    }
    private static func step(_ key: String, _ rule: String, _ n: Int) -> String {
        switch rule {
        case "daily": return HabitRules.addDays(key, n)
        case "weekly": return HabitRules.addDays(key, 7 * n)
        case "monthly": return addMonths(key, n)
        case "yearly": return addMonths(key, 12 * n)
        default:
            // Weekdays: the next Monday–Friday.
            var next = HabitRules.addDays(key, 1)
            while [0, 6].contains(HabitRules.weekday(next)) { next = HabitRules.addDays(next, 1) }
            return next
        }
    }

    /// The next copy's days for a task planned on `day` and/or due on `deadline`, finished on `completedDay`.
    /// Both move by the same number of steps, until the copy lands after `completedDay`. A task with neither
    /// is planned one step after the day it was finished. Nil for an unknown rule.
    static func nextDays(day: String?, deadline: String?, rule: String?, every: Int, completedDay: String) -> (day: String?, deadline: String?)? {
        guard let rule, valid(rule) else { return nil }
        let n = max(1, every)
        var next = day ?? deadline ?? completedDay, steps = 0
        repeat { next = step(next, rule, n); steps += 1 } while next <= completedDay && steps < 5000
        func move(_ key: String?) -> String? {
            guard let key else { return nil }
            // Months are counted in one go, so skipping several months doesn't drift.
            if rule == "monthly" { return addMonths(key, n * steps) }
            if rule == "yearly" { return addMonths(key, 12 * n * steps) }
            var result = key
            for _ in 0..<steps { result = step(result, rule, n) }
            return result
        }
        if day == nil && deadline == nil { return (next, nil) }
        return (move(day), move(deadline))
    }

    /// FNV-1a over the text's bytes with a seed.
    private static func fnv(_ text: String, seed: UInt32) -> UInt32 {
        var hash = seed
        for byte in text.utf8 { hash ^= UInt32(byte); hash = hash &* 16_777_619 }
        return hash
    }
    /// The ID of the copy of task `id` planned (or due) on `day`: the same on every device.
    static func occurrenceID(_ id: UUID, day: String) -> UUID {
        let text = id.uuidString.lowercased() + "|" + day
        var hex = Array((0..<4).map { i -> String in
            let seed = UInt32(2_166_136_261) ^ (UInt32(i + 1) &* 0x9E37_79B9)
            let value = String(fnv(text, seed: seed), radix: 16)
            return String(repeating: "0", count: 8 - value.count) + value
        }.joined())
        hex[12] = "5"
        hex[16] = Character(String((Int(String(hex[16]), radix: 16)! & 3) | 8, radix: 16))
        let s = String(hex)
        let formatted = [s.prefix(8), s.dropFirst(8).prefix(4), s.dropFirst(12).prefix(4), s.dropFirst(16).prefix(4), s.dropFirst(20)].joined(separator: "-")
        return UUID(uuidString: formatted)!
    }

    /// "Every 2 weeks", or "" for a task that doesn't repeat.
    static func label(rule: String?, every: Int?) -> String {
        guard let rule, valid(rule) else { return "" }
        if rule == "weekdays" { return "Every weekday" }
        let n = max(1, every ?? 1)
        let unit = ["daily": "day", "weekly": "week", "monthly": "month", "yearly": "year"][rule]!
        return n == 1 ? "Every \(unit)" : "Every \(n) \(unit)s"
    }
    /// The editor's value for a rule ("weekly:2"), or "".
    static func choice(rule: String?, every: Int?) -> String { valid(rule) ? "\(rule!):\(max(1, every ?? 1))" : "" }
}
