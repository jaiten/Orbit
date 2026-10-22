import Foundation

/// Day categories are mutually exclusive, independent of the list a task belongs to.
enum TaskGroup: String, CaseIterable, Identifiable {
    case today = "Today", overdue = "Overdue", upcoming = "Upcoming"
    case undated = "No date", someday = "Someday", completed = "Completed"
    var id: String { rawValue }
    static func group(day: String?, someday: Bool, completed: Bool, today: String) -> TaskGroup {
        if completed { return .completed }
        if someday { return .someday }
        guard let day else { return .undated }
        if day == today { return .today }
        return day < today ? .overdue : .upcoming
    }
}
