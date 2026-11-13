// Generated from shared/rewards.json by windows/scripts/generate.cjs. Do not edit.
import Foundation

enum RewardsData {
    struct Badge: Identifiable, Hashable { let id: String; let title: String; let detail: String; let metric: String; let goal: Int; let unlocks: String? }
    static let freeAccents = ["coral", "sage", "lavender", "honey", "teal", "blue"]
    static let badges = [
        Badge(id: "first-step", title: "First step", detail: "Finish your first task or habit", metric: "completions", goal: 1, unlocks: nil),
        Badge(id: "showing-up", title: "Showing up", detail: "Get something done on 3 days", metric: "activeDays", goal: 3, unlocks: nil),
        Badge(id: "getting-going", title: "Getting going", detail: "10 things done", metric: "completions", goal: 10, unlocks: "rose"),
        Badge(id: "a-week-in", title: "A week in", detail: "Get something done on 7 days", metric: "activeDays", goal: 7, unlocks: "forest"),
        Badge(id: "momentum", title: "Momentum", detail: "50 things done", metric: "completions", goal: 50, unlocks: "ocean"),
        Badge(id: "hundred", title: "Hundred", detail: "100 things done", metric: "completions", goal: 100, unlocks: "plum"),
        Badge(id: "a-month-in", title: "A month in", detail: "Get something done on 30 days", metric: "activeDays", goal: 30, unlocks: "gold"),
        Badge(id: "steady", title: "Steady", detail: "250 things done", metric: "completions", goal: 250, unlocks: "midnight"),
        Badge(id: "five-hundred", title: "Five hundred", detail: "500 things done", metric: "completions", goal: 500, unlocks: nil),
        Badge(id: "hundred-days", title: "Hundred days", detail: "Get something done on 100 days", metric: "activeDays", goal: 100, unlocks: nil),
        Badge(id: "thousand", title: "Thousand", detail: "1,000 things done", metric: "completions", goal: 1000, unlocks: nil),
    ]
}
