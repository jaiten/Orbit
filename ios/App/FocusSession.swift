import ActivityKit
import SwiftUI

/// A focus timer for one task. It shows in Today, and on the Lock Screen and Dynamic Island when Live
/// Activities are allowed; without them it still runs in the app.
@MainActor final class FocusSession: ObservableObject {
    static let shared = FocusSession()
    @Published var title: String?
    @Published var endsAt: Date?
    @Published var startedAt = Date.now
    @Published var taskID: UUID?
    private var activity: Activity<FocusAttributes>?
    private let defaults = UserDefaults.standard
    func restore() {
        activity = Activity<FocusAttributes>.activities.first
        if let activity {
            title = activity.attributes.title; taskID = activity.attributes.taskID
            endsAt = activity.content.state.endsAt; startedAt = activity.content.state.startedAt
        } else if let saved = defaults.string(forKey: "focus.title"), defaults.double(forKey: "focus.endsAt") > 0 {
            title = saved; taskID = defaults.string(forKey: "focus.taskID").flatMap(UUID.init(uuidString:))
            endsAt = Date(timeIntervalSince1970: defaults.double(forKey: "focus.endsAt"))
            startedAt = Date(timeIntervalSince1970: defaults.double(forKey: "focus.startedAt"))
        } else { title = nil; endsAt = nil; taskID = nil }
        if let endsAt, endsAt <= .now { Task { await stop() } }
    }
    /// Timer lengths offered for a task: these, plus the task's own duration (Windows: TIMER_CHOICES).
    static let choices = [15, 30, 60, 120]
    static func minutes(for task: PlannerTask) -> Int { min(240, max(5, task.durationMinutes)) }
    static func options(for task: PlannerTask) -> [Int] { Array(Set(choices + [minutes(for: task)])).sorted() }
    static func label(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        let text = hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
        return text + (minutes == 60 ? " hour" : " hours")
    }

    func start(_ task: PlannerTask, minutes: Int? = nil) async throws {
        await stop()
        let length = minutes ?? Self.minutes(for: task)
        let start = Date.now, end = start.addingTimeInterval(Double(length) * 60)
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: FocusAttributes(taskID: task.id, title: task.title), content: ActivityContent(state: .init(startedAt: start, endsAt: end), staleDate: end), pushType: nil)
        }
        title = task.title; taskID = task.id; startedAt = start; endsAt = end
        defaults.set(task.title, forKey: "focus.title"); defaults.set(task.id.uuidString, forKey: "focus.taskID")
        defaults.set(start.timeIntervalSince1970, forKey: "focus.startedAt"); defaults.set(end.timeIntervalSince1970, forKey: "focus.endsAt")
    }
    func stop() async {
        for item in Activity<FocusAttributes>.activities { await item.end(nil, dismissalPolicy: .immediate) }
        activity = nil; title = nil; endsAt = nil; taskID = nil
        for key in ["focus.title", "focus.taskID", "focus.startedAt", "focus.endsAt"] { defaults.removeObject(forKey: key) }
    }
    func stopIfMatching(_ id: UUID) async {
        if taskID == id || Activity<FocusAttributes>.activities.contains(where: { $0.attributes.taskID == id }) { await stop() }
    }
}
