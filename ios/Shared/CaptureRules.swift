import Foundation

/// Quick add rules (Settings → Quick add rules), synced as one preferences record like Day starts at.
/// - progressWords: words that always turn on start & finish for a new task with one of them in its title.
/// - shortcuts: abbreviations quick add expands ("mtg" → "meeting with the team"); cases in shared/test-cases/shortcuts.json.
/// The same screen holds the Someday visibility rules (SomedayRules), synced as their own record.
/// Mirrors windows/ui/capture-rules.js; cases in shared/test-cases/progress-learning.json.
enum CaptureRules {
    static let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private static let wordsKey = "captureRuleProgressWords", updatedKey = "captureRulesUpdatedAt"
    private static let shortcutsKey = "captureRuleShortcuts"

    struct Shortcut: Codable, Equatable, Hashable {
        var abbr: String
        var text: String
    }
    private static var defaults: UserDefaults { DayTheme.sharedDefaults ?? .standard }

    static var progressWords: [String] { defaults.stringArray(forKey: wordsKey) ?? [] }
    /// Milliseconds since 1970 when the rules last changed; 0 if they never have (nothing to sync yet).
    static var updatedAt: Double { defaults.double(forKey: updatedKey) }

    static var shortcuts: [Shortcut] {
        guard let data = defaults.data(forKey: shortcutsKey) else { return [] }
        return ((try? JSONDecoder().decode([Shortcut].self, from: data)) ?? []).filter { !$0.abbr.isEmpty && !$0.text.isEmpty }
    }

    /// Changed in Settings on this device.
    static func save(progressWords: [String]) {
        defaults.set(progressWords, forKey: wordsKey)
        defaults.set((Date.now.timeIntervalSince1970 * 1000).rounded(), forKey: updatedKey)
    }
    static func save(shortcuts: [Shortcut]) {
        defaults.set(try? JSONEncoder().encode(shortcuts), forKey: shortcutsKey)
        defaults.set((Date.now.timeIntervalSince1970 * 1000).rounded(), forKey: updatedKey)
    }
    /// The synced record's fields (besides id).
    static var payload: [String: Any] {
        ["progressWords": progressWords, "shortcuts": shortcuts.map { ["abbr": $0.abbr, "text": $0.text] }, "updatedAt": updatedAt]
    }
    /// Received from another device.
    static func receive(_ payload: [String: Any]) {
        defaults.set((payload["progressWords"] as? [String] ?? []).filter { !$0.isEmpty }, forKey: wordsKey)
        let shortcuts = (payload["shortcuts"] as? [[String: Any]] ?? []).compactMap { item -> Shortcut? in
            guard let abbr = item["abbr"] as? String, let text = item["text"] as? String, !abbr.isEmpty, !text.isEmpty else { return nil }
            return Shortcut(abbr: abbr, text: text)
        }
        defaults.set(try? JSONEncoder().encode(shortcuts), forKey: shortcutsKey)
        defaults.set(payload["updatedAt"] as? Double ?? 0, forKey: updatedKey)
    }

    /// "mtg = meeting with the team" per line (also -> or →); the last line for a word wins.
    static func parseShortcuts(_ text: String) -> [Shortcut] {
        var table: [String: Shortcut] = [:], order: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let separators = ["=", "->", "→"]
            guard let separator = separators.compactMap({ line.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { continue }
            let abbr = line[..<separator.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
            let text = line[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !abbr.isEmpty, abbr.count <= 24, !abbr.contains(where: \.isWhitespace), !text.isEmpty, text.count <= 200 else { continue }
            if table[abbr] == nil { order.append(abbr) }
            table[abbr] = Shortcut(abbr: abbr, text: text)
        }
        return order.compactMap { table[$0] }
    }
    static func lines(_ shortcuts: [Shortcut]) -> String { shortcuts.map { "\($0.abbr) = \($0.text)" }.joined(separator: "\n") }

    /// A whole word matching an abbreviation, ignoring case and trailing punctuation, becomes its text.
    /// Mirrors OrbitPlanning.expand in windows/ui/planning.js.
    static func expand(_ input: String, shortcuts: [Shortcut] = CaptureRules.shortcuts) -> String {
        guard !shortcuts.isEmpty else { return input }
        var table: [String: String] = [:]
        for shortcut in shortcuts where !shortcut.abbr.isEmpty && !shortcut.text.isEmpty { table[shortcut.abbr.lowercased()] = shortcut.text }
        var result = "", word = ""
        func flush() {
            guard !word.isEmpty else { return }
            if let text = table[word.lowercased()] { result += text }
            else {
                let bare = String(word.reversed().drop { ".,!?;:".contains($0) }.reversed())
                if !bare.isEmpty, let text = table[bare.lowercased()] { result += text + word.dropFirst(bare.count) } else { result += word }
            }
            word = ""
        }
        for character in input {
            if character.isWhitespace { flush(); result.append(character) } else { word.append(character) }
        }
        flush()
        return result
    }

    /// When a space has just finished a word that is an abbreviation, the text with it expanded; otherwise nil.
    static func expandingLastWord(_ text: String, previous: String) -> String? {
        guard text.count == previous.count + 1, text.hasPrefix(previous), text.last == " ", !shortcuts.isEmpty else { return nil }
        let body = text.dropLast()
        let start = body.lastIndex(where: \.isWhitespace).map { body.index(after: $0) } ?? body.startIndex
        let word = String(body[start...])
        guard !word.isEmpty else { return nil }
        let expanded = expand(word)
        return expanded == word ? nil : String(body[..<start]) + expanded + " "
    }
}
