import Foundation

/// Quick add rules (Settings → Quick add rules), synced as one preferences record like Day starts at.
/// - places: "@mums" puts a task on the next of that place's weekdays (0 = Sunday), today included.
/// - progressWords: words that always turn on start & finish for a new task with one of them in its title.
/// Mirrors windows/ui/capture-rules.js; cases in shared/test-cases/quick-add.json and progress-learning.json.
enum CaptureRules {
    struct Place: Equatable, Codable, Hashable { var name: String; var days: [Int] }

    static let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private static let placesKey = "captureRulePlaces", wordsKey = "captureRuleProgressWords", updatedKey = "captureRulesUpdatedAt"
    private static var defaults: UserDefaults { DayTheme.sharedDefaults ?? .standard }
    private static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    static var places: [Place] {
        guard let data = defaults.data(forKey: placesKey) else { return [] }
        return (try? JSONDecoder().decode([Place].self, from: data)) ?? []
    }
    static var progressWords: [String] { defaults.stringArray(forKey: wordsKey) ?? [] }
    /// Milliseconds since 1970 when the rules last changed; 0 if they never have (nothing to sync yet).
    static var updatedAt: Double { defaults.double(forKey: updatedKey) }

    /// Changed in Settings on this device.
    static func save(places: [Place]? = nil, progressWords: [String]? = nil) {
        if let places { defaults.set(try? JSONEncoder().encode(places), forKey: placesKey) }
        if let progressWords { defaults.set(progressWords, forKey: wordsKey) }
        defaults.set((Date.now.timeIntervalSince1970 * 1000).rounded(), forKey: updatedKey)
    }
    /// The synced record's fields (besides id).
    static var payload: [String: Any] {
        ["places": places.map { ["name": $0.name, "days": $0.days] as [String: Any] }, "progressWords": progressWords, "updatedAt": updatedAt]
    }
    /// Received from another device.
    static func receive(_ payload: [String: Any]) {
        let received = (payload["places"] as? [[String: Any]] ?? []).compactMap { item -> Place? in
            guard let name = item["name"] as? String, let days = item["days"] as? [Int], !name.isEmpty else { return nil }
            return Place(name: name, days: days.filter { (0...6).contains($0) })
        }
        defaults.set(try? JSONEncoder().encode(received), forKey: placesKey)
        defaults.set((payload["progressWords"] as? [String] ?? []).filter { !$0.isEmpty }, forKey: wordsKey)
        defaults.set(payload["updatedAt"] as? Double ?? 0, forKey: updatedKey)
    }

    /// "mums = Thu, Fri" per line → [Place(name: "mums", days: [4, 5])]. Also "weekdays", "weekends", "mon-wed".
    static func parsePlaces(_ text: String) -> [Place] {
        text.components(separatedBy: "\n").compactMap { line -> Place? in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == "=" || $0 == ":" })
            guard parts.count == 2 else { return nil }
            var name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            if name.hasPrefix("@") { name.removeFirst() }
            guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || "_'-".contains($0) }) else { return nil }
            var days = Set<Int>()
            for word in parts[1].lowercased().split(whereSeparator: { $0 == "," || $0.isWhitespace }) where word != "and" {
                if word.hasPrefix("weekday") { days.formUnion(1...5); continue }
                if word.hasPrefix("weekend") { days.formUnion([0, 6]); continue }
                let ends = word.split(separator: "-").map { dayNames.firstIndex(of: String($0.prefix(3))) }
                guard let from = ends.first ?? nil else { continue }
                if ends.count == 2, let to = ends[1] {
                    var day = from
                    while true { days.insert(day); if day == to { break }; day = (day + 1) % 7 }
                } else { days.insert(from) }
            }
            return days.isEmpty ? nil : Place(name: name, days: days.sorted())
        }
    }
    static func placeLines(_ places: [Place]) -> String {
        places.map { place in place.name + " = " + place.days.map { dayNames[$0].capitalized }.joined(separator: ", ") }.joined(separator: "\n")
    }
}
