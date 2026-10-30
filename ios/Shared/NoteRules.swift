import Foundation

enum NoteIcons {
    struct Choice: Identifiable {
        let symbol: String
        let name: String
        var id: String { symbol }
    }
    static let defaultSymbol = "doc.text"
    static let choices: [Choice] = [
        .init(symbol: "doc.text", name: "Document"), .init(symbol: "book.closed", name: "Book"),
        .init(symbol: "pencil", name: "Pencil"), .init(symbol: "lightbulb", name: "Idea"),
        .init(symbol: "star", name: "Star"), .init(symbol: "heart", name: "Heart"),
        .init(symbol: "bookmark", name: "Bookmark"), .init(symbol: "flag", name: "Flag"),
        .init(symbol: "calendar", name: "Calendar"), .init(symbol: "checklist", name: "Checklist"),
        .init(symbol: "briefcase", name: "Work"), .init(symbol: "house", name: "Home"),
        .init(symbol: "leaf", name: "Leaf"), .init(symbol: "sun.max", name: "Sun"),
        .init(symbol: "moon", name: "Moon"), .init(symbol: "cup.and.saucer", name: "Coffee"),
        .init(symbol: "airplane", name: "Travel"), .init(symbol: "map", name: "Map"),
        .init(symbol: "music.note", name: "Music"), .init(symbol: "gift", name: "Gift")
    ]
    static func symbol(_ value: String?) -> String { choices.first { $0.symbol == value }?.symbol ?? defaultSymbol }
    static func name(_ value: String) -> String { choices.first { $0.symbol == value }?.name ?? "Document" }
}

/// Long captures become a titled note instead of a to-do.
/// Mirrors windows/ui/notes.js; cases in shared/test-cases/notes.json.
enum NoteRules {
    /// Captures longer than this (or with a line break) become notes.
    static let threshold = 120
    private static let titleLimit = 60

    static func isNote(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains("\n") || value.count > threshold
    }

    /// The first line, the first short sentence, or the opening words become the title.
    static func split(_ text: String) -> (title: String, body: String) {
        let value = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = value.components(separatedBy: "\n")
        if lines.count > 1 {
            return (lines[0].trimmingCharacters(in: .whitespaces),
                    lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let regex = try! NSRegularExpression(pattern: #"^(.+?[.!?])\s+(\S.*)$"#)
        if let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let first = Range(match.range(at: 1), in: value), let rest = Range(match.range(at: 2), in: value),
           value[first].count <= 80 {
            var title = String(value[first])
            if title.hasSuffix(".") { title.removeLast() }
            return (title, String(value[rest]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if value.count <= titleLimit { return (value, "") }
        var title = ""
        for word in value.split(whereSeparator: \.isWhitespace) {
            if !title.isEmpty && title.count + 1 + word.count > titleLimit { break }
            title = title.isEmpty ? String(word.prefix(titleLimit)) : title + " " + word
        }
        return (title + "…", value)
    }

    /// One line under a note's title: the start of its body.
    static func snippet(_ body: String) -> String {
        String(body.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(140))
    }
}
