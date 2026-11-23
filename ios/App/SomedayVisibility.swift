import EventKit
import Foundation

extension SomedayRules {
    /// Tags whose rules match `day`. A calendar rule reads every shown calendar with its title, so a calendar
    /// that appears twice (for example iCloud and a subscribed copy) still works. Same as Windows.
    @MainActor static func activeTags(on day: Date, rules: [Rule], bridge: CalendarBridge) -> Set<String> {
        guard !rules.isEmpty else { return [] }
        let key = PlannerLogic.dayKey(day)
        let sources = rules.contains { $0.trigger.usesCalendar } ? bridge.calendars.filter(bridge.isShown) : []
        let events = sources.isEmpty ? [] : bridge.events(on: day)
        return Set(rules.filter { rule in
            guard rule.trigger.usesCalendar else { return rule.matches(key, eventTitles: nil) }
            let ids = Set(sources.filter { $0.title == rule.calendar }.map(\.calendarIdentifier))
            guard !ids.isEmpty else { return false }
            let titles = events.filter { ids.contains($0.calendar?.calendarIdentifier ?? "") && $0.status != .canceled }
                .compactMap(\.title)
            return rule.matches(key, eventTitles: titles)
        }.map(\.tag))
    }

    /// Open Someday tasks a rule brings to `day` (today or later), for Calendar.
    @MainActor static func tasks(_ tasks: [PlannerTask], on day: Date, rules: [Rule], bridge: CalendarBridge) -> [PlannerTask] {
        guard !rules.isEmpty, PlannerLogic.dayKey(day) >= PlannerLogic.today else { return [] }
        let tagged = tasks.filter { !$0.note && $0.completedAt == nil && $0.listID == TodayRules.somedayID && !SomedayRules.tags(in: $0.title).isEmpty }
        guard !tagged.isEmpty else { return [] }
        let active = activeTags(on: day, rules: rules, bridge: bridge)
        guard !active.isEmpty else { return [] }
        return tagged.filter { !SomedayRules.tags(in: $0.title).isDisjoint(with: active) }
    }

    /// Open tasks outside Someday that already carry a tag with a rule: made before the rule, so still on their own day.
    static func untaggedByRule(_ tasks: [PlannerTask], rules: [Rule]) -> [PlannerTask] {
        let ruled = Set(rules.map(\.tag))
        guard !ruled.isEmpty else { return [] }
        return tasks.filter { !$0.note && $0.completedAt == nil && $0.listID != TodayRules.somedayID && !SomedayRules.tags(in: $0.title).isDisjoint(with: ruled) }
    }
}
