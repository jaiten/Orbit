import SwiftUI
import SwiftData

@MainActor final class UndoJournal: ObservableObject {
    static let shared = UndoJournal()
    enum Kind: String {
        case deleted = "Deleted", moved = "Moved", imported = "Imported", edited = "Edited", added = "Added"
        /// For the shake prompt: "Undo delete?"
        var verb: String {
            switch self {
            case .deleted: return "delete"
            case .moved: return "move"
            case .imported: return "import"
            case .edited: return "edit"
            case .added: return "addition"
            }
        }
    }
    struct Change { let before: [String: String]; let after: [String: String]; let keys: Set<String>; let created: Date; var kind: Kind = .moved }
    @Published private(set) var change: Change?
    @Published private(set) var shakeChange: Change?
    /// Records a change if it is worth undoing (see `kind`); `kind` forces one, as imports do.
    func record(before: [String: String], after: [String: String], kind forced: Kind? = nil) {
        let keys = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        guard !keys.isEmpty else { return }
        let kind = forced ?? Self.kind(keys: keys, before: before, after: after)
        let latest = Change(before: before.filter { keys.contains($0.key) }, after: after.filter { keys.contains($0.key) }, keys: keys, created: .now, kind: kind ?? (keys.allSatisfy { before[$0] == nil } ? .added : .edited))
        shakeChange = latest
        if kind != nil { change = latest }
    }

    /// Only deleting something or moving a task (another list or day, Later, Someday, into a habit) offers
    /// Undo. Ticks, check-ins and edits are easy to redo by hand. Same rule as Windows (planner-tools.cjs).
    static func kind(keys: Set<String>, before: [String: String], after: [String: String]) -> Kind? {
        let removed = keys.filter { before[$0] != nil && after[$0] == nil }
        let added = keys.filter { before[$0] == nil && after[$0] != nil }
        if !removed.isEmpty { return added.contains { $0.hasPrefix("tasks/") || $0.hasPrefix("habits/") } ? .moved : .deleted }
        let moved = keys.contains { key in
            guard key.hasPrefix("tasks/"), let old = before[key].flatMap({ try? SyncRecords.object($0) }),
                  let now = after[key].flatMap({ try? SyncRecords.object($0) }) else { return false }
            return ["listID", "localDate", "dueDate"].contains { field in
                String(describing: old[field] ?? NSNull()) != String(describing: now[field] ?? NSNull())
            }
        }
        return moved ? .moved : nil
    }
    func undo(in context: ModelContext, latest: Bool = false) throws {
        guard let change = latest ? shakeChange : change else { return }
        guard latest || Date.now.timeIntervalSince(change.created) < 30 else { dismiss(); return }
        let current = try SyncRecords.snapshots(context)
        guard change.keys.allSatisfy({ current[$0] == change.after[$0] }) else {
            if latest { shakeChange = nil }
            dismiss()
            throw NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "This item changed on another device. Undo was stopped to preserve those changes."])
        }
        do {
        for key in change.keys {
            let deleted = change.before[key] == nil
            var payload = try SyncRecords.object(change.before[key] ?? change.after[key]!)
            payload["updatedAt"] = Date.now.timeIntervalSince1970 * 1000
            try SyncRecords.apply(["key": key, "payload": payload, "deleted": deleted], context: context)
        }
        try Mutations.save(context, undoable: false)
        shakeChange = nil
        dismiss()
        } catch { context.rollback(); throw error }
    }
    func dismiss() { change = nil }
}
