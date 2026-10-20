import EventKit
import EventKitUI
import SwiftUI

struct CalendarDraft: Identifiable {
    let id = UUID()
    let taskID: UUID
    let event: EKEvent
}

@MainActor final class CalendarBridge: ObservableObject {
    static let shared = CalendarBridge()
    let store = EKEventStore()
    @Published var events: [EKEvent] = []
    @Published var connected = false
    private var observer: NSObjectProtocol?
    private init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in CalendarBridge.shared.reload() }
        }
        reload()
    }
    func connect() async throws {
        guard try await store.requestFullAccessToEvents() else {
            throw NSError(domain: "Orbit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Calendar access is off. You can enable it in iPhone Settings → Orbit → Calendars."])
        }
        UserDefaults.standard.set(true, forKey: "calendarConnected")
        reload()
    }
    func disconnect() { UserDefaults.standard.set(false, forKey: "calendarConnected"); reload() }
    func reload() {
        connected = UserDefaults.standard.bool(forKey: "calendarConnected") && EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard connected else { events = []; return }
        let start = Calendar.current.startOfDay(for: .now), end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
    }
    func events(on day: Date) -> [EKEvent] {
        guard connected else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
    }
    func draft(for task: PlannerTask) async throws -> CalendarDraft {
        if !connected { try await connect() }
        let previous = UserDefaults.standard.string(forKey: "calendarEvent." + task.id.uuidString).flatMap { store.event(withIdentifier: $0) }
        let event = previous ?? EKEvent(eventStore: store)
        if previous == nil {
            guard let calendar = store.defaultCalendarForNewEvents else { throw NSError(domain: "Orbit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Add a writable calendar in iPhone Settings first."]) }
            event.calendar = calendar
        }
        event.title = task.title; event.notes = task.notes
        event.startDate = task.hasTime ? (task.dueDate ?? .now) : Calendar.current.startOfDay(for: task.dueDate ?? .now); event.isAllDay = !task.hasTime
        event.endDate = task.hasTime ? event.startDate.addingTimeInterval(Double(task.durationMinutes) * 60) : Calendar.current.date(byAdding: .day, value: 1, to: event.startDate)!
        return CalendarDraft(taskID: task.id, event: event)
    }
}

struct CalendarEventEditor: UIViewControllerRepresentable {
    let draft: CalendarDraft
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = CalendarBridge.shared.store; controller.event = draft.event; controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    class Coordinator: NSObject, EKEventEditViewDelegate {
        let parent: CalendarEventEditor
        init(_ parent: CalendarEventEditor) { self.parent = parent }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            Task { @MainActor in
                if action == .saved, let id = controller.event?.eventIdentifier { UserDefaults.standard.set(id, forKey: "calendarEvent." + parent.draft.taskID.uuidString) }
                CalendarBridge.shared.reload(); parent.dismiss()
            }
        }
    }
}

struct CalendarEventRow: View {
    let event: EKEvent
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Event").font(.subheadline.weight(.medium))
                Text(event.calendar.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                if !event.isAllDay { Text(event.endDate.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary) }
            }.font(.caption).monospacedDigit()
        }.padding(12).frame(minHeight: 60).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}
