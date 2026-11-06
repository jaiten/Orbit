import Foundation

/// Groups pages by when they were last edited, as Apple Notes does: Today, Yesterday, Previous 7 Days,
/// Previous 30 Days, then each earlier month of this year, then each earlier year. Order is kept.
enum NoteDateGroup {
    struct Group<Item> { let title: String; var items: [Item] }

    static func title(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days <= 7 { return "Previous 7 Days" }
        if days <= 30 { return "Previous 30 Days" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.wide))
        }
        return String(calendar.component(.year, from: date))
    }

    /// `items` newest first; consecutive items with the same title share a group.
    static func groups<Item>(_ items: [Item], date: (Item) -> Date, now: Date = .now, calendar: Calendar = .current) -> [Group<Item>] {
        var result: [Group<Item>] = []
        for item in items {
            let title = title(for: date(item), now: now, calendar: calendar)
            if result.last?.title == title { result[result.count - 1].items.append(item) }
            else { result.append(Group(title: title, items: [item])) }
        }
        return result
    }
}
