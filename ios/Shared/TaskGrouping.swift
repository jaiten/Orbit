import Foundation

/// Day categories are mutually exclusive, independent of the list a task belongs to.
enum TaskDateGroup: String, CaseIterable, Identifiable {
    case today = "Today", overdue = "Overdue", upcoming = "Upcoming"
    case someday = "Someday", completed = "Completed"
    var id: String { rawValue }
    static func group(day: String?, someday: Bool, completed: Bool, today: String) -> TaskDateGroup {
        if completed { return .completed }
        if someday { return .someday }
        guard let day else { return .someday }
        if day == today { return .today }
        return day < today ? .overdue : .upcoming
    }
}
