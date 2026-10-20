// Generated from shared/onboarding.json by windows/scripts/generate.cjs. Do not edit.
import Foundation

enum OnboardingData {
    struct ExampleList { let id: String; let name: String; let color: String }
    struct ExampleTask { let id: String; let title: String; let time: Int?; let minutes: Int?; let list: String?; let someday: Bool }
    struct ExampleHabit { let id: String; let title: String; let frequencyRule: String; let target: Int; let color: String }
    struct HabitSuggestion { let title: String; let frequencyRule: String; let target: Int; let reminderMinutes: Int? }
    static let exampleLists = [
        ExampleList(id: "00000000-0000-4000-8000-0000000e0001", name: "Personal", color: "sage"),
    ]
    static let exampleTasks = [
        ExampleTask(id: "00000000-0000-4000-8000-0000000e0101", title: "Morning walk", time: 480, minutes: 30, list: nil, someday: false),
        ExampleTask(id: "00000000-0000-4000-8000-0000000e0102", title: "Focus on one thing", time: 600, minutes: 90, list: nil, someday: false),
        ExampleTask(id: "00000000-0000-4000-8000-0000000e0103", title: "Call someone you miss", time: nil, minutes: nil, list: "00000000-0000-4000-8000-0000000e0001", someday: false),
        ExampleTask(id: "00000000-0000-4000-8000-0000000e0104", title: "Plan a weekend away", time: nil, minutes: nil, list: nil, someday: true),
    ]
    static let exampleHabits = [
        ExampleHabit(id: "00000000-0000-4000-8000-0000000e0201", title: "Drink water", frequencyRule: "DAILY", target: 6, color: "sage"),
        ExampleHabit(id: "00000000-0000-4000-8000-0000000e0202", title: "Read a few pages", frequencyRule: "DAILY", target: 1, color: "lavender"),
        ExampleHabit(id: "00000000-0000-4000-8000-0000000e0203", title: "Move your body", frequencyRule: "WEEKLY", target: 3, color: "clay"),
    ]
    static let habitSuggestions = [
        HabitSuggestion(title: "Drink water", frequencyRule: "DAILY", target: 6, reminderMinutes: nil),
        HabitSuggestion(title: "Read 10 pages", frequencyRule: "DAILY", target: 1, reminderMinutes: nil),
        HabitSuggestion(title: "Stretch", frequencyRule: "WEEKDAYS", target: 1, reminderMinutes: nil),
        HabitSuggestion(title: "Walk outside", frequencyRule: "DAILY", target: 1, reminderMinutes: nil),
        HabitSuggestion(title: "Exercise", frequencyRule: "WEEKLY", target: 3, reminderMinutes: nil),
        HabitSuggestion(title: "Plan tomorrow", frequencyRule: "DAILY", target: 1, reminderMinutes: 1260),
    ]
}
