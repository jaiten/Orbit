import Foundation

enum PlannerBackup {
    static func encode(_ records: [String: String]) throws -> Data {
        let entries = try records.sorted { $0.key < $1.key }.map { ["key": $0.key, "payload": try SyncRecords.object($0.value)] as [String: Any] }
        return try JSONSerialization.data(withJSONObject: ["format": "orbit-backup", "version": 1, "records": entries], options: [.sortedKeys, .prettyPrinted])
    }
    static func decode(_ data: Data) throws -> [[String: Any]] {
        guard data.count <= 50_000_000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["format"] as? String == "orbit-backup", object["version"] as? Int == 1, let records = object["records"] as? [[String: Any]], records.count <= 100_000 else { throw CocoaError(.coderReadCorrupt) }
        var seen: Set<String> = []
        for record in records {
            guard let key = record["key"] as? String, seen.insert(key).inserted, let p = record["payload"] as? [String: Any], let id = p["id"] as? String, UUID(uuidString: id) != nil, try JSONSerialization.data(withJSONObject: p).count <= 100_000 else { throw CocoaError(.coderReadCorrupt) }
            let entity = String(key.split(separator: "/").first ?? "")
            if entity == "habit_logs" {
                guard let habit = p["habitID"] as? String, UUID(uuidString: habit) != nil, let day = p["dayKey"] as? String, day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil, key == "habit_logs/" + habit.lowercased() + "-" + day, let count = p["count"] as? Int, count >= 0 else { throw CocoaError(.coderReadCorrupt) }
            } else {
                guard ["tasks", "habits", "lists", "idea_prompts"].contains(entity), key == entity + "/" + id.lowercased(), let name = p[entity == "lists" ? "name" : entity == "idea_prompts" ? "text" : "title"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.coderReadCorrupt) }
            }
            if entity == "habits" { guard let target = p["target"] as? Int, target > 0, ["DAILY", "WEEKLY"].contains(p["frequencyRule"] as? String ?? "") else { throw CocoaError(.coderReadCorrupt) } }
        }
        return records
    }
}
