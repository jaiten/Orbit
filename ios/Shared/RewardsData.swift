// Generated from shared/rewards.json by windows/scripts/generate.cjs. Do not edit.
import Foundation

enum RewardsData {
    struct Badge: Identifiable, Hashable { let id: String; let title: String; let detail: String; let metric: String; let goal: Int; let unlocks: String? }
    static let freeAccents = ["coral", "sage", "blue"]
    static let retiredAccents: [String] = ["ocean", "forest", "gold"]
    static let badges = [
        Badge(id: "first-step", title: "First step", detail: "Finish your first task or habit", metric: "completions", goal: 1, unlocks: nil),
        Badge(id: "showing-up", title: "Showing up", detail: "Get something done on 3 days", metric: "activeDays", goal: 3, unlocks: "lavender"),
        Badge(id: "getting-going", title: "Getting going", detail: "10 things done", metric: "completions", goal: 10, unlocks: "teal"),
        Badge(id: "a-week-in", title: "A week in", detail: "Get something done on 7 days", metric: "activeDays", goal: 7, unlocks: "honey"),
        Badge(id: "twenty-five", title: "Twenty-five", detail: "25 things done", metric: "completions", goal: 25, unlocks: nil),
        Badge(id: "two-weeks-in", title: "Two weeks in", detail: "Get something done on 14 days", metric: "activeDays", goal: 14, unlocks: nil),
        Badge(id: "momentum", title: "Momentum", detail: "50 things done", metric: "completions", goal: 50, unlocks: "rose"),
        Badge(id: "hundred", title: "Hundred", detail: "100 things done", metric: "completions", goal: 100, unlocks: nil),
        Badge(id: "a-month-in", title: "A month in", detail: "Get something done on 30 days", metric: "activeDays", goal: 30, unlocks: "plum"),
        Badge(id: "two-months-in", title: "Two months in", detail: "Get something done on 60 days", metric: "activeDays", goal: 60, unlocks: nil),
        Badge(id: "steady", title: "Steady", detail: "250 things done", metric: "completions", goal: 250, unlocks: "midnight"),
        Badge(id: "five-hundred", title: "Five hundred", detail: "500 things done", metric: "completions", goal: 500, unlocks: nil),
        Badge(id: "hundred-days", title: "Hundred days", detail: "Get something done on 100 days", metric: "activeDays", goal: 100, unlocks: nil),
        Badge(id: "half-a-year", title: "Half a year", detail: "Get something done on 180 days", metric: "activeDays", goal: 180, unlocks: nil),
        Badge(id: "thousand", title: "Thousand", detail: "1,000 things done", metric: "completions", goal: 1000, unlocks: nil),
        Badge(id: "a-year-in", title: "A year in", detail: "Get something done on 365 days", metric: "activeDays", goal: 365, unlocks: nil),
        Badge(id: "two-thousand", title: "Two thousand", detail: "2,000 things done", metric: "completions", goal: 2000, unlocks: nil),
    ]
}
