import Foundation
import SwiftData

@Model final class TaskList {
    @Attribute(.unique) var id: UUID
    var name: String
    var color: String
    var sortOrder: Int
    var updatedAt: Date
    init(name: String, color: String = "sage", sortOrder: Int = 0) {
        id = UUID(); self.name = name; self.color = color
        self.sortOrder = sortOrder; updatedAt = .now
    }
}

@Model final class PlannerTask {
    var conversionData: String? = nil
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var listID: UUID?
    var dueDate: Date?
    var hasTime: Bool
    var durationMinutes: Int
    var reminders: [Date]
    var recurrenceRule: String
    var priority: Int
    var tags: [String]
    var subtasks: [Subtask]
    var completedAt: Date?
    var nextOccurrenceID: UUID?
    var sortOrder: Int
    var updatedAt: Date
    init(title: String, dueDate: Date? = nil, hasTime: Bool = false, listID: UUID? = nil) {
        id = UUID(); self.title = title; notes = ""; self.listID = listID
        self.dueDate = dueDate; self.hasTime = hasTime; durationMinutes = 30
        reminders = []; recurrenceRule = ""; priority = 0; tags = []; subtasks = []
        completedAt = nil; sortOrder = 0; updatedAt = .now
    }
}

struct Subtask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var completed = false
}

@Model final class Habit {
    var conversionData: String? = nil
    @Attribute(.unique) var id: UUID
    var title: String
    /// DAILY or WEEKLY; target is completions in the calendar period.
    var frequencyRule: String
    var target: Int
    var color: String
    var icon: String
    var reminderMinutes: Int?
    var nudgeMinutes: Int?
    var createdAt: Date
    var updatedAt: Date
    init(title: String, frequencyRule: String = "DAILY", target: Int = 1,
         color: String = "sage", icon: String = "leaf") {
        id = UUID(); self.title = title; self.frequencyRule = frequencyRule
        self.target = target; self.color = color; self.icon = icon
        createdAt = .now; updatedAt = .now
    }
}

@Model final class HabitLog {
    @Attribute(.unique) var id: UUID
    var habitID: UUID
    /// Local calendar day, not a UTC midnight timestamp.
    var dayKey: String
    var count: Int
    var updatedAt: Date
    init(habitID: UUID, dayKey: String, count: Int = 1) {
        id = UUID(); self.habitID = habitID; self.dayKey = dayKey
        self.count = count; updatedAt = .now
    }
}

@Model final class IdeaPrompt {
    @Attribute(.unique) var id: UUID
    var text: String
    var shownAt: Date?
    var dismissed: Bool
    var updatedAt: Date
    init(text: String) {
        id = UUID(); self.text = text; dismissed = false; updatedAt = .now
    }
}

extension PlannerTask {
    /// The task's local calendar day ("YYYY-MM-DD"), or nil when it has no date.
    var day: String? { dueDate.map { PlannerLogic.dayKey($0) } }
}
