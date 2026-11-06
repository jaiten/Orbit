import Foundation

/// Day categories are mutually exclusive, independent of the list a task belongs to.
enum TaskDateGroup: String, CaseIterable, Identifiable {
    case today = "Today", upcoming = "Upcoming"
    case someday = "Someday", completed = "Completed"
    var id: String { rawValue }
    static func group(day: String?, someday: Bool, completed: Bool, today: String) -> TaskDateGroup {
        if completed { return .completed }
        if someday { return .someday }
        guard let day else { return .someday }
        // Open tasks from earlier days stay on Today; there is no separate Overdue group.
        return day <= today ? .today : .upcoming
    }
}
