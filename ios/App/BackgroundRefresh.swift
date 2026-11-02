import BackgroundTasks
import SwiftData
import WidgetKit

/// Background refresh: iOS wakes Orbit now and then (it chooses when, usually a few times a day for
/// apps you open often) to pull changes from your other devices, so widgets, reminders and the app
/// are current before you open it. Uploads of local edits ride along. Signed-out copies do nothing.
enum BackgroundRefresh {
    /// Listed under BGTaskSchedulerPermittedIdentifiers in project.yml.
    static let identifier = "com.jaiten.orbit.refresh"

    /// Asks for the next wake-up, no sooner than 30 minutes from now. Called when Orbit leaves the
    /// screen and after each background run.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor static func run(_ container: ModelContainer) async {
        schedule()
        await SyncService.shared.run(container.mainContext)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
