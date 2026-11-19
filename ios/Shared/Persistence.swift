import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([TaskList.self, PlannerTask.self, Habit.self, HabitLog.self, IdeaPrompt.self, SyncEntry.self])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        let group = Bundle.main.object(forInfoDictionaryKey: "OrbitAppGroup") as? String
        let shared = group.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        #if DEBUG && targetEnvironment(simulator)
        // Unsigned preview builds can run without App Group entitlements.
        let directory = try shared ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        #else
        guard let directory = shared else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey:
                "The shared Orbit container is unavailable. Check App Groups in Signing & Capabilities for both targets."])
        }
        #endif
        let config = ModelConfiguration("Orbit", schema: schema,
            url: directory.appendingPathComponent("Orbit.store"), cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
