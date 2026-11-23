import Foundation

/// Visibility rules keep a task in Someday and decide whether Today should include it.
enum SomedayRules {
    enum Trigger: String, CaseIterable, Codable {
        case event, noEvent, dates, weeks, months

        var label: String {
            switch self {
            case .event: "Calendar contains event"
            case .noEvent: "Calendar has no matching event"
            case .dates: "Date or date range"
            case .weeks: "Every few weeks"
            case .months: "Every few months"
            }
        }
        var usesCalendar: Bool { self == .event || self == .noEvent }
    }

    struct Rule: Identifiable, Codable, Equatable {
        var id = UUID().uuidString.lowercased()
        var tag = ""
        var trigger: Trigger = .event
        var calendar = ""
        var title = ""
        var start = ""
        var end = ""
        var interval = 1

        var valid: Bool {
            guard SomedayRules.tags(in: "@" + tag) == [tag], !tag.isEmpty else { return false }
            if trigger.usesCalendar { return !calendar.isEmpty && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard let date = HabitRules.date(start), HabitRules.key(date) == start else { return false }
            if trigger == .dates {
                return end.isEmpty || (HabitRules.date(end).map(HabitRules.key) == end && end >= start)
            }
            return (1...52).contains(interval)
        }

        func matches(_ day: String, eventTitles: [String]?) -> Bool {
            guard valid else { return false }
            if trigger.usesCalendar {
                guard let eventTitles else { return false }
                let found = eventTitles.contains { $0.range(of: title.trimmingCharacters(in: .whitespacesAndNewlines), options: .caseInsensitive) != nil }
                return trigger == .event ? found : !found
            }
            guard day >= start else { return false }
            if trigger == .dates { return day <= (end.isEmpty ? start : end) }
            guard let anchor = HabitRules.date(start), let target = HabitRules.date(day) else { return false }
            if trigger == .weeks { return Int(target.timeIntervalSince(anchor) / 86400) % (7 * interval) == 0 }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let a = calendar.dateComponents([.year, .month, .day], from: anchor)
            let b = calendar.dateComponents([.year, .month, .day], from: target)
            guard let ay = a.year, let by = b.year, let am = a.month, let bm = b.month else { return false }
            return a.day == b.day && ((by - ay) * 12 + bm - am) % interval == 0
        }

    }

    /// Tags whose rules match `day`. `calendars` are the titles of the shown calendars; `events` gives the
    /// day's events in them as (calendar title, event title), read only when a calendar rule needs it.
    /// Every calendar with a rule's title counts, so one that appears twice still works. Same as Windows.
    static func activeTags(on day: String, rules: [Rule], calendars: () -> Set<String>,
                           events: () -> [(calendar: String, title: String)]) -> Set<String> {
        guard !rules.isEmpty else { return [] }
        let usesCalendar = rules.contains { $0.trigger.usesCalendar }
        let shown = usesCalendar ? calendars() : []
        let found = usesCalendar && !shown.isEmpty ? events() : []
        return Set(rules.filter { rule in
            guard rule.trigger.usesCalendar else { return rule.matches(day, eventTitles: nil) }
            guard shown.contains(rule.calendar) else { return false }
            return rule.matches(day, eventTitles: found.filter { $0.calendar == rule.calendar }.map(\.title))
        }.map(\.tag))
    }

    /// Whether a task is on Today for `day`: a Someday task with an active @tag, otherwise the usual rules.
    static func isSomedayShown(_ title: String, active: Set<String>) -> Bool {
        !active.isEmpty && !tags(in: title).isDisjoint(with: active)
    }

    /// Calendar rules need EventKit, which widgets don't read: the app keeps today's result for them.
    private static let cacheKey = "somedayCalendarTags"
    static func cacheCalendarTags(_ tags: Set<String>, on day: String) {
        let value = [day] + tags.sorted()
        if defaults.stringArray(forKey: cacheKey) != value { defaults.set(value, forKey: cacheKey) }
    }
    static func cachedCalendarTags(on day: String) -> Set<String> {
        guard let value = defaults.stringArray(forKey: cacheKey), value.first == day else { return [] }
        return Set(value.dropFirst())
    }

    static let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    static let storageKey = "somedayVisibilityRules"
    static var defaults: UserDefaults { DayTheme.sharedDefaults ?? .standard }
    static var updatedAt: Double { defaults.double(forKey: storageKey + "UpdatedAt") }
    static var rules: [Rule] { decode(defaults.data(forKey: storageKey) ?? Data()) }
    static func decode(_ data: Data) -> [Rule] {
        ((try? JSONDecoder().decode([Rule].self, from: data)) ?? []).filter(\.valid)
    }
    static func tags(in title: String) -> Set<String> {
        // Full tokens only. An address like name@domain does not opt a task in.
        let pattern = #"(?<![\p{L}\p{N}_@'-])@([\p{L}\p{N}_'-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return Set(regex.matches(in: title, range: NSRange(title.startIndex..., in: title)).compactMap {
            Range($0.range(at: 1), in: title).map { title[$0].lowercased() }
        })
    }
    static func save(_ rules: [Rule]) throws {
        defaults.set(try JSONEncoder().encode(rules), forKey: storageKey)
        defaults.set((Date.now.timeIntervalSince1970 * 1000).rounded(), forKey: storageKey + "UpdatedAt")
    }
    static func record() throws -> [String: Any] {
        ["id": recordID.uuidString.lowercased(), "rules": try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules)), "updatedAt": updatedAt]
    }
    static func receive(_ payload: [String: Any]) {
        guard let rules = payload["rules"] as? [[String: Any]], let data = try? JSONSerialization.data(withJSONObject: rules) else { return }
        defaults.set(data, forKey: storageKey)
        defaults.set(payload["updatedAt"] as? Double ?? 0, forKey: storageKey + "UpdatedAt")
    }
}
