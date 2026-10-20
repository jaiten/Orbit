import Foundation

enum SyncMerge {
    private static func clean(_ value: [String: Any]) -> [String: Any] {
        value.filter { key, item in
            if key == "id" || key == "updatedAt" || item is NSNull { return false }
            if let text = item as? String, text.isEmpty { return false }
            if let array = item as? [Any], array.isEmpty { return false }
            return true
        }
    }
    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        let left = (try? JSONSerialization.data(withJSONObject: [a ?? NSNull()], options: [.sortedKeys]))
        let right = (try? JSONSerialization.data(withJSONObject: [b ?? NSNull()], options: [.sortedKeys]))
        return left == right
    }
    static func merge(local: [String: Any], remote: [String: Any], base: [String: Any]?) -> [String: Any]? {
        if equal(clean(local), clean(remote)) { return remote }
        guard let base else { return nil }
        var result = remote
        for key in Set(local.keys).union(remote.keys).union(base.keys) where key != "id" && key != "updatedAt" {
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
        if let frequency = payload["frequencyRule"] as? String { lines.append("\(payload["target"] as? Int ?? 1) times \(frequency == "WEEKLY" ? "a week" : "a day")") }
        if let completed = payload["completedAt"], !(completed is NSNull) { lines.append("Completed") }
        return lines.joined(separator: "\n")
    }
}
