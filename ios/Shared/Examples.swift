import Foundation
import SwiftData

/// Example tasks, a list and habits from shared/onboarding.json. They use fixed IDs, so adding them on
/// two devices never duplicates anything, and removing them only ever touches these records.
@MainActor enum Examples {
    static let listIDs = Set(OnboardingData.exampleLists.compactMap { UUID(uuidString: $0.id) })
    static let taskIDs = Set(OnboardingData.exampleTasks.compactMap { UUID(uuidString: $0.id) })
    static let habitIDs = Set(OnboardingData.exampleHabits.compactMap { UUID(uuidString: $0.id) })

    /// Adds the examples for today. Ones already here (perhaps synced from another device) are left alone.
    static func add(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        let lists = try context.fetch(FetchDescriptor<TaskList>())
        let tasks = Set(try context.fetch(FetchDescriptor<PlannerTask>()).map(\.id))
        let habits = Set(try context.fetch(FetchDescriptor<Habit>()).map(\.id))
        for (index, example) in OnboardingData.exampleLists.enumerated() {
            guard let id = UUID(uuidString: example.id), !lists.contains(where: { $0.id == id }) else { continue }
            let list = TaskList(name: example.name, color: example.color, sortOrder: lists.count + index); list.id = id
            context.insert(list)
        }
        let day = calendar.startOfDay(for: now)
        for (index, example) in OnboardingData.exampleTasks.enumerated() {
            guard let id = UUID(uuidString: example.id), !tasks.contains(id) else { continue }
            let start = example.time.flatMap { calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: day) }
            let task = PlannerTask(title: example.title, dueDate: start ?? day, hasTime: start != nil, listID: example.list.flatMap(UUID.init(uuidString:)))
            task.id = id; task.sortOrder = index
            if let minutes = example.minutes { task.durationMinutes = minutes }
            context.insert(task)
            if example.someday { try TodayRules.moveToSomeday(task, in: context) }
        }
        for example in OnboardingData.exampleHabits {
            guard let id = UUID(uuidString: example.id), !habits.contains(id) else { continue }
            let habit = Habit(title: example.title, frequencyRule: example.frequencyRule, target: example.target, color: example.color)
            habit.id = id; habit.createdAt = now
            context.insert(habit)
        }
        try Mutations.save(context)
    }

    static func present(in context: ModelContext) throws -> Bool {
        let tasks = try context.fetch(FetchDescriptor<PlannerTask>()), habits = try context.fetch(FetchDescriptor<Habit>())
        let lists = try context.fetch(FetchDescriptor<TaskList>())
        return tasks.contains { taskIDs.contains($0.id) } || habits.contains { habitIDs.contains($0.id) } || lists.contains { listIDs.contains($0.id) }
    }

    /// Deletes the examples and their check-ins. The example list stays if you added your own tasks to it.
    static func remove(in context: ModelContext) throws {
        let tasks = try context.fetch(FetchDescriptor<PlannerTask>())
        let used = Set(tasks.filter { !taskIDs.contains($0.id) }.compactMap(\.listID))
        tasks.filter { taskIDs.contains($0.id) }.forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<Habit>()).filter { habitIDs.contains($0.id) }.forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<HabitLog>()).filter { habitIDs.contains($0.habitID) }.forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<TaskList>()).filter { listIDs.contains($0.id) && !used.contains($0.id) }.forEach { context.delete($0) }
        try Mutations.save(context)
    }
}
