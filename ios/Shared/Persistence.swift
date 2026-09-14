import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([TaskList.self, PlannerTask.self, Habit.self, HabitLog.self, IdeaPrompt.self])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        guard let group = Bundle.main.object(forInfoDictionaryKey: "DayOSAppGroup") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey:
                "The shared DayOS container is unavailable. Check App Groups in Signing & Capabilities for both targets."])
        }
        let config = ModelConfiguration("DayOS", schema: schema,
            url: directory.appendingPathComponent("DayOS.store"), cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
