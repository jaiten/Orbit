import ActivityKit
import SwiftUI

@MainActor final class FocusSession: ObservableObject {
    static let shared = FocusSession()
    @Published var title: String?
    @Published var endsAt: Date?
    @Published var startedAt = Date.now
    private var activity: Activity<FocusAttributes>?
    func restore() {
        activity = Activity<FocusAttributes>.activities.first
        title = activity?.attributes.title
        endsAt = activity?.content.state.endsAt
        startedAt = activity?.content.state.startedAt ?? .now
        if let endsAt, endsAt <= .now { Task { await stop() } }
    }
    func start(_ task: PlannerTask) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enable Live Activities for Orbit in iPhone Settings to show a focus timer on your Lock Screen."])
        }
        await stop()
        let start = Date.now, end = start.addingTimeInterval(Double(min(240, max(5, task.durationMinutes))) * 60)
        activity = try Activity.request(attributes: FocusAttributes(taskID: task.id, title: task.title), content: ActivityContent(state: .init(startedAt: start, endsAt: end), staleDate: end), pushType: nil)
        title = task.title; startedAt = start; endsAt = end
    }
    func stop() async {
        for item in Activity<FocusAttributes>.activities { await item.end(nil, dismissalPolicy: .immediate) }
        activity = nil; title = nil; endsAt = nil
    }
    func stopIfMatching(_ id: UUID) async {
        if Activity<FocusAttributes>.activities.contains(where: { $0.attributes.taskID == id }) { await stop() }
    }
}
