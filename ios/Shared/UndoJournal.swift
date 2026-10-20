import SwiftUI
import SwiftData

@MainActor final class UndoJournal: ObservableObject {
    static let shared = UndoJournal()
    struct Change { let before: [String: String]; let after: [String: String]; let keys: Set<String>; let created: Date }
    @Published private(set) var change: Change?
    func record(before: [String: String], after: [String: String]) {
        let keys = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        guard !keys.isEmpty else { return }
        change = Change(before: before.filter { keys.contains($0.key) }, after: after.filter { keys.contains($0.key) }, keys: keys, created: .now)
    }
    func undo(in context: ModelContext) throws {
        guard let change, Date.now.timeIntervalSince(change.created) < 30 else { dismiss(); return }
        let current = try SyncRecords.snapshots(context)
        guard change.keys.allSatisfy({ current[$0] == change.after[$0] }) else {
            dismiss()
            throw NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "This item changed on another device. Undo was stopped to preserve those changes."])
        }
        for key in change.keys {
            let deleted = change.before[key] == nil
            var payload = try SyncRecords.object(change.before[key] ?? change.after[key]!)
            payload["updatedAt"] = Date.now.timeIntervalSince1970 * 1000
            try SyncRecords.apply(["key": key, "payload": payload, "deleted": deleted], context: context)
        }
        try Mutations.save(context, undoable: false)
        dismiss()
    }
    func dismiss() { change = nil }
}
