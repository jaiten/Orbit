import Foundation
import SwiftData

/// Durable outbox and server revision, saved in the same transaction as each edit.
@Model final class SyncEntry {
    @Attribute(.unique) var key: String
    var payload: String
    var tombstone: Bool
    var revision: Int
    var mutation: String
    var dirty: Bool
    var conflict: String?
    var basePayload: String? = nil
    init(key: String, payload: String) {
        self.key = key; self.payload = payload; tombstone = false; revision = 0
        mutation = UUID().uuidString.lowercased(); dirty = true
    }
}

@MainActor enum SyncRecords {
    static func json(_ object: Any) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
    }
    static func object(_ string: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        return object
    }
    static func stamp(_ date: Date?) -> Any { date.map { $0.timeIntervalSince1970 * 1000 } ?? NSNull() }
    static func id(_ uuid: UUID?) -> Any { uuid.map { $0.uuidString.lowercased() } ?? NSNull() }
    static func snapshots(_ context: ModelContext) throws -> [String: String] {
        let pendingDeletions = Set(context.deletedModelsArray.map(\.persistentModelID))
        var result: [String: String] = [:]
        func add(_ entity: String, _ key: String, _ value: [String: Any]) throws { result[entity + "/" + key] = try json(value) }
        for t in try context.fetch(FetchDescriptor<PlannerTask>()).filter({ !$0.isDeleted && !pendingDeletions.contains($0.persistentModelID) }) {
            try add("tasks", t.id.uuidString.lowercased(), ["conversionData": t.conversionData ?? NSNull() as Any, "id": id(t.id), "title": t.title, "notes": t.notes, "listID": id(t.listID), "dueDate": t.hasTime ? stamp(t.dueDate) : NSNull(), "localDate": t.dueDate.map { PlannerLogic.dayKey($0) } ?? NSNull() as Any, "hasTime": t.hasTime, "durationMinutes": t.durationMinutes, "reminders": t.reminders.map { $0.timeIntervalSince1970 * 1000 }, "recurrenceRule": t.recurrenceRule, "priority": t.priority, "tags": t.tags, "subtasks": t.subtasks.map { ["id": id($0.id), "title": $0.title, "completed": $0.completed] }, "completedAt": stamp(t.completedAt), "nextOccurrenceID": id(t.nextOccurrenceID), "sortOrder": t.sortOrder, "updatedAt": stamp(t.updatedAt)])
        }
        for h in try context.fetch(FetchDescriptor<Habit>()).filter({ !$0.isDeleted && !pendingDeletions.contains($0.persistentModelID) }) {
            try add("habits", h.id.uuidString.lowercased(), ["conversionData": h.conversionData ?? NSNull() as Any, "id": id(h.id), "title": h.title, "frequencyRule": h.frequencyRule, "target": h.target, "color": h.color, "icon": h.icon, "reminderMinutes": h.reminderMinutes ?? NSNull() as Any, "nudgeMinutes": h.nudgeMinutes ?? NSNull() as Any, "createdAt": stamp(h.createdAt), "updatedAt": stamp(h.updatedAt)])
        }
        for l in try context.fetch(FetchDescriptor<HabitLog>()).filter({ !$0.isDeleted && !pendingDeletions.contains($0.persistentModelID) }) {
            // The stable key makes independent check-ins on two devices conflict safely.
            try add("habit_logs", l.habitID.uuidString.lowercased() + "-" + l.dayKey, ["id": id(l.id), "habitID": id(l.habitID), "dayKey": l.dayKey, "count": l.count, "updatedAt": stamp(l.updatedAt)])
        }
        for l in try context.fetch(FetchDescriptor<TaskList>()).filter({ !$0.isDeleted && !pendingDeletions.contains($0.persistentModelID) }) { try add("lists", l.id.uuidString.lowercased(), ["id": id(l.id), "name": l.name, "color": l.color, "sortOrder": l.sortOrder, "updatedAt": stamp(l.updatedAt)]) }
        for i in try context.fetch(FetchDescriptor<IdeaPrompt>()).filter({ !$0.isDeleted && !pendingDeletions.contains($0.persistentModelID) }) { try add("idea_prompts", i.id.uuidString.lowercased(), ["id": id(i.id), "text": i.text, "shownAt": stamp(i.shownAt), "dismissed": i.dismissed, "updatedAt": stamp(i.updatedAt)]) }
        return result
    }
    static func capture(_ context: ModelContext, snapshots supplied: [String: String]? = nil) throws {
        let snapshots = try supplied ?? snapshots(context)
        let entries = try context.fetch(FetchDescriptor<SyncEntry>()).filter { $0.key != "owner" }
        let existing = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
        for (key, payload) in snapshots {
            if let entry = existing[key] {
                if entry.payload != payload || entry.tombstone { entry.payload = payload; entry.tombstone = false; entry.dirty = true; entry.mutation = UUID().uuidString.lowercased() }
            } else { context.insert(SyncEntry(key: key, payload: payload)) }
        }
        for entry in entries where snapshots[entry.key] == nil && !entry.tombstone { entry.tombstone = true; entry.dirty = true; entry.mutation = UUID().uuidString.lowercased() }
    }
    static func bind(_ user: String, context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<SyncEntry>())
        if let owner = entries.first(where: { $0.key == "owner" }) {
            guard owner.payload == user else { throw NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "This planner belongs to another account. Sign in with the original account."]) }
        } else { let owner = SyncEntry(key: "owner", payload: user); owner.dirty = false; context.insert(owner); try context.save() }
    }
    static func apply(_ record: [String: Any], context: ModelContext) throws {
        guard let key = record["key"] as? String, let p = record["payload"] as? [String: Any], let rawID = p["id"] as? String, let uuid = UUID(uuidString: rawID) else { throw CocoaError(.coderReadCorrupt) }
        let deleted = record["deleted"] as? Bool ?? false
        func date(_ name: String) -> Date? { (p[name] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } }
        func uid(_ name: String) -> UUID? { (p[name] as? String).flatMap(UUID.init(uuidString:)) }
        switch key.split(separator: "/").first {
        case "tasks":
            let old = try context.fetch(FetchDescriptor<PlannerTask>()).first { $0.id == uuid }
            if deleted { if let old { context.delete(old) }; return }
            let t = old ?? PlannerTask(title: p["title"] as? String ?? "Task"); if old == nil { t.id = uuid; context.insert(t) }
            t.conversionData = p["conversionData"] as? String; t.title = p["title"] as? String ?? t.title; t.notes = p["notes"] as? String ?? ""; t.listID = uid("listID"); t.hasTime = p["hasTime"] as? Bool ?? false
            if t.hasTime { t.dueDate = date("dueDate") } else if let day = p["localDate"] as? String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; t.dueDate = f.date(from: day) } else { t.dueDate = nil }
            t.durationMinutes = p["durationMinutes"] as? Int ?? 30; t.reminders = (p["reminders"] as? [Double] ?? []).map { Date(timeIntervalSince1970: $0 / 1000) }; t.recurrenceRule = p["recurrenceRule"] as? String ?? ""; t.priority = p["priority"] as? Int ?? 0; t.tags = p["tags"] as? [String] ?? []
            t.subtasks = (p["subtasks"] as? [[String: Any]] ?? []).compactMap { s in guard let id = (s["id"] as? String).flatMap(UUID.init(uuidString:)), let title = s["title"] as? String else { return nil }; return Subtask(id: id, title: title, completed: s["completed"] as? Bool ?? false) }
            t.completedAt = date("completedAt"); t.nextOccurrenceID = uid("nextOccurrenceID"); t.sortOrder = p["sortOrder"] as? Int ?? 0; t.updatedAt = date("updatedAt") ?? .now
        case "habits":
            let old = try context.fetch(FetchDescriptor<Habit>()).first { $0.id == uuid }
            if deleted { if let old { context.delete(old) }; return }
            let h = old ?? Habit(title: p["title"] as? String ?? "Habit"); if old == nil { h.id = uuid; context.insert(h) }
            h.conversionData = p["conversionData"] as? String; h.title = p["title"] as? String ?? h.title; h.target = max(1, p["target"] as? Int ?? 1); h.frequencyRule = p["frequencyRule"] as? String ?? "DAILY"; h.color = p["color"] as? String ?? "clay"; h.icon = p["icon"] as? String ?? "leaf"; h.reminderMinutes = p["reminderMinutes"] as? Int; h.nudgeMinutes = p["nudgeMinutes"] as? Int; h.createdAt = date("createdAt") ?? .now; h.updatedAt = date("updatedAt") ?? .now
        case "habit_logs":
            guard let habitID = uid("habitID"), let day = p["dayKey"] as? String else { throw CocoaError(.coderReadCorrupt) }
            let old = try context.fetch(FetchDescriptor<HabitLog>()).first { $0.habitID == habitID && $0.dayKey == day }
            if deleted { if let old { context.delete(old) }; return }
            let l = old ?? HabitLog(habitID: habitID, dayKey: day); if old == nil { context.insert(l) }; l.id = uuid; l.count = max(0, p["count"] as? Int ?? 0); l.updatedAt = date("updatedAt") ?? .now
        case "lists":
            let old = try context.fetch(FetchDescriptor<TaskList>()).first { $0.id == uuid }; if deleted { if let old { context.delete(old) }; return }
            let l = old ?? TaskList(name: p["name"] as? String ?? "List"); if old == nil { l.id = uuid; context.insert(l) }; l.name = p["name"] as? String ?? l.name; l.color = p["color"] as? String ?? "sage"; l.sortOrder = p["sortOrder"] as? Int ?? 0; l.updatedAt = date("updatedAt") ?? .now
        case "idea_prompts":
            let old = try context.fetch(FetchDescriptor<IdeaPrompt>()).first { $0.id == uuid }; if deleted { if let old { context.delete(old) }; return }
            let i = old ?? IdeaPrompt(text: p["text"] as? String ?? ""); if old == nil { i.id = uuid; context.insert(i) }; i.text = p["text"] as? String ?? ""; i.shownAt = date("shownAt"); i.dismissed = p["dismissed"] as? Bool ?? false; i.updatedAt = date("updatedAt") ?? .now
        default: throw CocoaError(.coderReadCorrupt)
        }
    }
}
