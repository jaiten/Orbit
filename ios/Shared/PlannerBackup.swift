import Foundation

/// The export format shared with Windows (windows/planner-tools.cjs): version 2 of `orbit-backup`.
/// Version 2 adds `exportedAt` and `app`; records are unchanged, so version 1 files still import.
@MainActor enum PlannerBackup {
    static func encode(_ records: [String: String], exportedAt: Date = .now) throws -> Data {
        let entries = try records.sorted { $0.key < $1.key }.map { ["key": $0.key, "payload": try SyncRecords.object($0.value)] as [String: Any] }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var object: [String: Any] = ["format": "orbit-backup", "version": 2, "exportedAt": formatter.string(from: exportedAt), "app": "Orbit", "records": entries]
        let photos = try NotePhotos.backupFiles(entries)
        if !photos.isEmpty { object["photoFiles"] = photos }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        guard data.count <= 50_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        return data
    }
    static func decode(_ data: Data) throws -> [[String: Any]] {
        guard data.count <= 50_000_000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["format"] as? String == "orbit-backup", [1, 2].contains(object["version"] as? Int ?? 0), let records = object["records"] as? [[String: Any]], records.count <= 100_000 else { throw CocoaError(.coderReadCorrupt) }
        var seen: Set<String> = []
        for record in records {
            guard let key = record["key"] as? String, seen.insert(key).inserted, let p = record["payload"] as? [String: Any], let id = p["id"] as? String, UUID(uuidString: id) != nil, try JSONSerialization.data(withJSONObject: p).count <= 100_000 else { throw CocoaError(.coderReadCorrupt) }
            let entity = String(key.split(separator: "/").first ?? "")
            if entity == "habit_logs" {
                guard let habit = p["habitID"] as? String, UUID(uuidString: habit) != nil, let day = p["dayKey"] as? String, day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil, key == "habit_logs/" + habit.lowercased() + "-" + day, let count = p["count"] as? Int, count >= 0 else { throw CocoaError(.coderReadCorrupt) }
            } else {
                guard ["tasks", "habits", "lists", "idea_prompts"].contains(entity), key == entity + "/" + id.lowercased(), let name = p[entity == "lists" ? "name" : entity == "idea_prompts" ? "text" : "title"] as? String, (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (entity == "tasks" && p["isNote"] as? Bool == true)) else { throw CocoaError(.coderReadCorrupt) }
            }
            if entity == "tasks" {
                guard p["notes"] is String, p["hasTime"] is Bool, p["recurrenceRule"] is String, p["reminders"] is [Double], p["tags"] is [String], let steps = p["subtasks"] as? [[String: Any]], steps.allSatisfy({ ($0["id"] as? String).flatMap(UUID.init(uuidString:)) != nil && $0["title"] is String && $0["completed"] is Bool }), let duration = p["durationMinutes"] as? Int, (5...1440).contains(duration), let priority = p["priority"] as? Int, (0...3).contains(priority) else { throw CocoaError(.coderReadCorrupt) }
            }
            if entity == "habits" { guard let target = p["target"] as? Int, target > 0, HabitRules.schedules.contains(p["frequencyRule"] as? String ?? "") else { throw CocoaError(.coderReadCorrupt) } }
        }
        return records
    }

    /// What an import would do: new items are added, identical ones skipped, and items that differ
    /// are listed so they are only replaced when the user says so.
    struct Plan { var added: [[String: Any]] = []; var same: [[String: Any]] = []; var changed: [[String: Any]] = [] }
    static func plan(current: [String: String], records: [[String: Any]]) -> Plan {
        var plan = Plan()
        for record in records {
            guard let key = record["key"] as? String, let mine = current[key].flatMap({ try? SyncRecords.object($0) }) else { plan.added.append(record); continue }
            if SyncMerge.sameContent(mine, record["payload"] as? [String: Any] ?? [:]) { plan.same.append(record) } else { plan.changed.append(record) }
        }
        return plan
    }
    static func title(_ record: [String: Any]) -> String {
        let p = record["payload"] as? [String: Any] ?? [:]
        return p["title"] as? String ?? p["name"] as? String ?? p["dayKey"] as? String ?? "Item"
    }

    /// Tasks as CSV, with the same columns and order as Windows. Dates and times are local to this device.
    static func tasksCSV(_ records: [[String: Any]], calendar: Calendar = .current) -> String {
        let payloads = records.compactMap { record -> (String, [String: Any])? in
            guard let key = record["key"] as? String, let payload = record["payload"] as? [String: Any] else { return nil }
            return (key, payload)
        }
        let lists = Dictionary(payloads.filter { $0.0.hasPrefix("lists/") }.compactMap { entry in
            (entry.1["id"] as? String).map { id in (id.lowercased(), entry.1["name"] as? String ?? "") }
        }, uniquingKeysWith: { first, _ in first })
        let someday = TodayRules.somedayID.uuidString.lowercased()
        func date(_ value: Any?) -> Date? { (value as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } }
        struct Row { var id, title, list, date, time, minutes, completed, notes, tags: String }
        let rows: [Row] = payloads.filter { $0.0.hasPrefix("tasks/") }.map { _, t in
            let due = (t["hasTime"] as? Bool == true) ? date(t["dueDate"]) : nil
            let clock = due.map { calendar.dateComponents([.hour, .minute], from: $0) }
            let listID = (t["listID"] as? String)?.lowercased()
            return Row(id: t["id"] as? String ?? "", title: t["title"] as? String ?? "",
                       list: listID == someday ? "Someday" : listID.flatMap { lists[$0] } ?? "Inbox",
                       date: due.map { PlannerLogic.dayKey($0, calendar: calendar) } ?? t["localDate"] as? String ?? "",
                       time: clock.map { String(format: "%02d:%02d", $0.hour ?? 0, $0.minute ?? 0) } ?? "",
                       minutes: due == nil ? "" : String(t["durationMinutes"] as? Int ?? 30),
                       completed: date(t["completedAt"]).map { PlannerLogic.dayKey($0, calendar: calendar) } ?? "",
                       notes: t["notes"] as? String ?? "", tags: (t["tags"] as? [String] ?? []).joined(separator: "; "))
        }.sorted { a, b in
            let (da, db) = (a.date.isEmpty ? "9999" : a.date, b.date.isEmpty ? "9999" : b.date)
            if da != db { return da < db }
            if a.time != b.time { return a.time < b.time }
            if a.title != b.title { return a.title < b.title }
            return a.id < b.id
        }
        func field(_ text: String) -> String {
            text.contains(where: { $0 == "\"" || $0 == "," || $0 == "\r" || $0 == "\n" }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
        }
        let header = "Title,List,Date,Time,Minutes,Completed,Notes,Tags,ID"
        let lines = rows.map { [$0.title, $0.list, $0.date, $0.time, $0.minutes, $0.completed, $0.notes, $0.tags, $0.id].map(field).joined(separator: ",") }
        return ([header] + lines).joined(separator: "\r\n") + "\r\n"
    }
}
