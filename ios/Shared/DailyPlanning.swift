import Foundation

/// Greedy placement into real time intervals; no calendar writes or model mutations.
enum DailyPlanning {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let minutes: Int
    }
    struct Block: Equatable {
        let start: Date
        let end: Date
    }
    struct Slot: Identifiable, Equatable {
        let item: Item
        let start: Date
        let end: Date
        var id: String { item.id }
    }
    struct Result {
        var slots: [Slot] = []
        var unscheduled: [Item] = []
    }
    static func suggest(_ items: [Item], from start: Date, to end: Date, busy: [Block]) -> Result {
        var result = Result()
        var occupied = busy.filter { $0.end > start && $0.start < end && $0.end > $0.start }
        for item in items {
            guard item.minutes > 0, end > start else { result.unscheduled.append(item); continue }
            let duration = Double(item.minutes) * 60
            var cursor = start
            for block in occupied.sorted(by: { $0.start < $1.start }) {
                if block.end <= cursor { continue }
                if cursor.addingTimeInterval(duration) <= block.start { break }
                cursor = max(cursor, block.end)
            }
            let finish = cursor.addingTimeInterval(duration)
            if finish <= end {
                result.slots.append(Slot(item: item, start: cursor, end: finish))
                occupied.append(Block(start: cursor, end: finish))
            } else { result.unscheduled.append(item) }
        }
        return result
    }
}

/// Calendar preferences are local to this iPhone, like the existing event links.
enum HabitCalendarPreferences {
    static func duration(for id: UUID, defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: "habitCalendarMinutes." + id.uuidString)
        return value > 0 ? min(240, max(5, value)) : 15
    }
    static func setDuration(_ minutes: Int, for id: UUID, defaults: UserDefaults = .standard) {
        defaults.set(min(240, max(5, minutes)), forKey: "habitCalendarMinutes." + id.uuidString)
    }
}
