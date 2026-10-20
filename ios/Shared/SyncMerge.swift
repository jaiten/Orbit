import Foundation
import CoreFoundation

enum SyncMerge {
    /// Metadata. `conversionData` is only a restore aid for Make It a Task/Habit, so two devices
    /// that converted the same item never need a review just because its encoding differs.
    private static let ignored: Set<String> = ["id", "updatedAt", "conversionData"]
    private static func clean(_ value: [String: Any]) -> [String: Any] {
        value.filter { key, item in
            if ignored.contains(key) || item is NSNull { return false }
            if let text = item as? String, text.isEmpty { return false }
            if let array = item as? [Any], array.isEmpty { return false }
            return true
        }
    }
    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        let left = a ?? NSNull(), right = b ?? NSNull()
        if left is NSNull || right is NSNull { return left is NSNull && right is NSNull }
        if let l = left as? NSNumber, let r = right as? NSNumber {
            guard (CFGetTypeID(l) == CFBooleanGetTypeID()) == (CFGetTypeID(r) == CFBooleanGetTypeID()) else { return false }
            // Date/JSON round trips can differ by a fraction of a millisecond.
            return abs(l.doubleValue - r.doubleValue) < 0.001
        }
        if let l = left as? String, let r = right as? String { return l == r }
        if let l = left as? [Any], let r = right as? [Any] { return l.count == r.count && zip(l, r).allSatisfy { equal($0.0, $0.1) } }
        if let l = left as? [String: Any], let r = right as? [String: Any] { return Set(l.keys).union(r.keys).allSatisfy { equal(l[$0], r[$0]) } }
        return false
    }
    static func merge(local: [String: Any], remote: [String: Any], base: [String: Any]?) -> [String: Any]? {
        if equal(clean(local), clean(remote)) { return remote }
        guard let base else { return nil }
        var result = remote
        for key in Set(local.keys).union(remote.keys).union(base.keys) where !ignored.contains(key) {
            if equal(local[key], remote[key]) || equal(local[key], base[key]) { continue }
            guard equal(remote[key], base[key]) else { return nil }
            result[key] = local[key]
        }
        result["updatedAt"] = max(local["updatedAt"] as? Double ?? 0, remote["updatedAt"] as? Double ?? 0)
        return result
    }
    static func summary(_ payload: [String: Any], deleted: Bool = false) -> String {
        if deleted { return "Removed item" }
        var lines = [payload["title"] as? String ?? payload["name"] as? String ?? "Item"]
        if let notes = payload["notes"] as? String, !notes.isEmpty { lines.append(notes) }
        if let count = payload["count"] as? Int { lines.append("\(count) check-ins") }
        if let day = payload["localDate"] as? String { lines.append("Planned for " + day) }
        if let frequency = payload["frequencyRule"] as? String { lines.append("\(HabitRules.label(frequency)), \(payload["target"] as? Int ?? 1) \(frequency == "WEEKLY" ? "a week" : "a day")") }
        if let completed = payload["completedAt"], !(completed is NSNull) { lines.append("Completed") }
        if let priority = payload["priority"] as? Int, priority > 0 { lines.append("Priority: " + ["Normal", "Low", "Medium", "High"][min(priority, 3)]) }
        if let tags = payload["tags"] as? [String], !tags.isEmpty { lines.append("Tags: " + tags.joined(separator: ", ")) }
        if let steps = payload["subtasks"] as? [[String: Any]], !steps.isEmpty { lines.append("Steps: " + steps.map { ($0["completed"] as? Bool == true ? "✓ " : "") + ($0["title"] as? String ?? "") }.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }
}
