import Foundation

/// What one line of quick add text becomes. `date` is a local calendar day ("YYYY-MM-DD"),
/// `time` is minutes after midnight. Habits and Someday items have no date.
struct QuickAddResult: Equatable {
    enum Kind: String { case task, habit }
    var kind: Kind
    var title: String
    var date: String?
    var time: Int?
    var schedule: String?
    var someday = false
    var list: String?
}

/// Which day plain text lands on: today, the day being viewed, or no day when adding to a list.
enum DefaultDay: Equatable { case today, day(String), undated }

/// Quick add grammar. Mirrors windows/ui/planning.js; phrases in shared/test-cases/quick-add.json.
enum QuickAdd {
    private static let day = "(sun|mon|tues?|wed(?:nes)?|weds|thu(?:rs?)?|thurs|fri|sat(?:ur)?)(?:day)?"
    private static let month = "(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\\.?"
    private static let weekdays = ["sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let numbers = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6]

    /// Removes matched phrases from the text as they are understood.
    private struct Text {
        var value: String
        mutating func take(_ pattern: String) -> [String?]? {
            let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
            let groups = (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } }
            if let range = Range(match.range, in: value) { value.replaceSubrange(range, with: " ") }
            return groups
        }
    }

    static func parse(_ input: String, defaultDay: DefaultDay = .today, now: Date = .now, calendar: Calendar = .current) -> QuickAddResult {
        var text = Text(value: " " + input.trimmingCharacters(in: .whitespacesAndNewlines) + " ")
        let someday = text.take(#"\ssomeday(?=\s)"#) != nil
        let list = text.take(#"\s#([\p{L}\p{N}_-]+)(?=\s)"#)?[1] ?? nil

        var schedule: String?
        for (pattern, value) in [(#"\s(?:every\s*day|daily)(?=\s)"#, "DAILY"), (#"\s(?:every\s+weekday|weekdays)(?=\s)"#, "WEEKDAYS"),
                                 (#"\s(?:every\s+weekend|weekends)(?=\s)"#, "WEEKENDS"), (#"\s(?:every\s+week|weekly)(?=\s)"#, "WEEKLY"),
                                 (#"\severy\s+"# + day + #"(?=\s)"#, "WEEKLY")] where schedule == nil {
            if text.take(pattern) != nil { schedule = value }
        }

        var time: Int?
        if let m = text.take(#"\s(?:at\s+)?(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)(?=\s)"#) {
            time = (Int(m[1]!)! % 12 + (m[3]!.lowercased() == "pm" ? 12 : 0)) * 60 + (m[2].flatMap { Int($0) } ?? 0)
        } else if let m = text.take(#"\s(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)(?=\s)"#) {
            time = Int(m[1]!)! * 60 + Int(m[2]!)!
        } else if text.take(#"\s(?:at\s+)?noon(?=\s)"#) != nil { time = 720 }

        let today = calendar.startOfDay(for: now)
        func adding(_ component: Calendar.Component, _ value: Int) -> Date { calendar.date(byAdding: component, value: value, to: today)! }
        func nextWeekday(_ weekday: Int, skipToday: Bool) -> Date {
            var offset = (weekday - (calendar.component(.weekday, from: today) - 1) + 7) % 7
            if offset == 0 && skipToday { offset = 7 }
            return adding(.day, offset)
        }
        var date: Date?
        if schedule == nil {
            if text.take(#"\s(?:on\s+)?(today|tonight)(?=\s)"#) != nil { date = today }
            else if text.take(#"\s(?:on\s+)?(tomorrow|tmrw|tmr)(?=\s)"#) != nil { date = adding(.day, 1) }
            else if let m = text.take(#"\sin\s+(\d+|an?|one|two|three|four|five|six)\s+(day|week|month)s?(?=\s)"#) {
                let n = numbers[m[1]!.lowercased()] ?? Int(m[1]!) ?? 1
                switch m[2]!.lowercased() {
                case "month": date = adding(.month, n)
                case "week": date = adding(.day, n * 7)
                default: date = adding(.day, n)
                }
            } else if text.take(#"\snext\s+week(?=\s)"#) != nil { date = nextWeekday(1, skipToday: true) }
            else if let m = text.take(#"\s(?:on\s+)?(next\s+|this\s+)?"# + day + #"(?=\s)"#) {
                let word = m[2]!.lowercased()
                date = nextWeekday(weekdays[String(word.prefix(3))] ?? 0, skipToday: m[1]?.lowercased().hasPrefix("next") == true)
            } else if let m = text.take(#"\s(?:on\s+)?"# + month + #"\s+(\d{1,2})(?:st|nd|rd|th)?(?=\s)"#) ?? text.take(#"\s(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+"# + month + #"(?=\s)"#) {
                let (monthWord, dayNumber) = m[1]!.first!.isNumber ? (m[2]!, m[1]!) : (m[1]!, m[2]!)
                let monthIndex = (months.firstIndex(of: String(monthWord.lowercased().prefix(3))) ?? 0) + 1
                let year = calendar.component(.year, from: today)
                date = calendar.date(from: DateComponents(year: year, month: monthIndex, day: Int(dayNumber)!))
                if let found = date, found < today { date = calendar.date(from: DateComponents(year: year + 1, month: monthIndex, day: Int(dayNumber)!)) }
            }
        }

        let title = text.value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s(?:on|at|by)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let schedule { return QuickAddResult(kind: .habit, title: title, date: nil, time: time, schedule: schedule, list: list) }
        if someday { return QuickAddResult(kind: .task, title: title, date: nil, time: nil, someday: true, list: list) }
        if date == nil {
            var fallback = defaultDay
            // Adding to a list: without date words the task stays in the list, undated.
            if fallback == .undated {
                if time == nil { return QuickAddResult(kind: .task, title: title, date: nil, time: nil, list: list) }
                fallback = .today
            }
            if case .day(let key) = fallback { return QuickAddResult(kind: .task, title: title, date: key, time: time, list: list) }
            date = today
            // A bare time that has already passed today means tomorrow.
            let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            if let time, time < minutes { date = adding(.day, 1) }
        }
        return QuickAddResult(kind: .task, title: title, date: PlannerLogic.dayKey(date!, calendar: calendar), time: time, list: list)
    }

    /// Text for the preview chip, e.g. "Habit · Weekdays · 7:00 AM" or "Task · Tomorrow · 6:00 PM · List: Personal".
    static func describe(_ result: QuickAddResult, now: Date = .now, calendar: Calendar = .current) -> String {
        guard !result.title.isEmpty else { return "" }
        let clock = result.time.map { minutes in
            // Time formats may use a narrow no-break space before AM/PM; the chip uses a plain space on both apps.
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now)!.formatted(date: .omitted, time: .shortened)
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        let list = result.list.map { "List: " + $0 }
        if result.kind == .habit { return (["Habit", HabitRules.label(result.schedule ?? "DAILY")] + [clock].compactMap { $0 }).joined(separator: " · ") }
        if result.someday { return (["Someday"] + [list].compactMap { $0 }).joined(separator: " · ") }
        guard let day = result.date else { return (["Task", "No date"] + [list].compactMap { $0 }).joined(separator: " · ") }
        let today = PlannerLogic.dayKey(now, calendar: calendar)
        let tomorrow = PlannerLogic.dayKey(calendar.date(byAdding: .day, value: 1, to: now)!, calendar: calendar)
        let label = day == today ? "Today" : day == tomorrow ? "Tomorrow"
            : (HabitRules.date(day).map { $0.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).weekday(.abbreviated).month(.abbreviated).day()) } ?? day)
        return (["Task", label] + [clock, list].compactMap { $0 }).joined(separator: " · ")
    }

    /// The local start of a parsed day, plus its time when there is one.
    static func start(of day: String, time: Int?, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        guard let time else { return start }
        return calendar.date(bySettingHour: time / 60, minute: time % 60, second: 0, of: start)
    }
}
