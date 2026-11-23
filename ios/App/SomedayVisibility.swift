import EventKit
import Foundation

extension SomedayRules {
    /// Tags whose rules match `day`, reading the shown calendars through CalendarBridge.
    @MainActor static func activeTags(on day: Date, rules: [Rule], bridge: CalendarBridge) -> Set<String> {
        let key = PlannerLogic.dayKey(day)
        let active = activeTags(on: key, rules: rules,
                   calendars: { Set(bridge.calendars.filter(bridge.isShown).map(\.title)) },
                   events: {
                       let shown = Set(bridge.calendars.filter(bridge.isShown).map(\.calendarIdentifier))
                       return bridge.events(on: day)
                           .filter { $0.status != .canceled && shown.contains($0.calendar?.calendarIdentifier ?? "") }
                           .map { (calendar: $0.calendar?.title ?? "", title: $0.title ?? "") }
                   })
        // Widgets can't read calendars: keep today's calendar-rule result for them.
        if key == PlannerLogic.today, bridge.connected {
            let calendarTags = Set(rules.filter { $0.trigger.usesCalendar && active.contains($0.tag) }.map(\.tag))
                .subtracting(rules.filter { !$0.trigger.usesCalendar && $0.matches(key, eventTitles: nil) }.map(\.tag))
            cacheCalendarTags(calendarTags, on: key)
        }
        return active
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
