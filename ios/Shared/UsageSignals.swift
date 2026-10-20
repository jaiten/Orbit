import Foundation

/// On-device, coarse counters only. No event titles, account data, or API calls.
enum UsageSignals {
    static func recordVisit(now: Date = .now, defaults: UserDefaults = .standard) {
        if defaults.object(forKey: "orbitFirstVisit") == nil { defaults.set(now.timeIntervalSince1970, forKey: "orbitFirstVisit") }
        let key = PlannerLogic.dayKey(now)
        guard defaults.string(forKey: "orbitLastVisit") != key else { return }
        defaults.set(key, forKey: "orbitLastVisit")
        defaults.set(defaults.integer(forKey: "orbitVisitDays") + 1, forKey: "orbitVisitDays")
        let hour = Calendar.current.component(.hour, from: now)
        var hours = defaults.dictionary(forKey: "orbitVisitHours") as? [String: Int] ?? [:]
        hours[String(hour), default: 0] += 1
        defaults.set(hours, forKey: "orbitVisitHours")
    }
    static func suggestedMinutes(defaults: UserDefaults = .standard) -> Int {
        let hours = defaults.dictionary(forKey: "orbitVisitHours") as? [String: Int] ?? [:]
        // Don't infer from a single visit; never recommend sleep hours.
        let candidates = hours.filter { (7...20).contains(Int($0.key) ?? -1) && $0.value >= 3 }
        let best = candidates.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first
        return (best.flatMap { Int($0.key) } ?? 18) * 60
    }
}
