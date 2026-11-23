import EventKit
import EventKitUI
import SwiftUI
import SwiftData

struct CalendarDraft: Identifiable {
    let id = UUID()
    /// The task the event was made from; nil when an existing calendar event is opened.
    let taskID: UUID?
    let event: EKEvent
}

@MainActor final class CalendarBridge: ObservableObject {
    static let shared = CalendarBridge()
    let store = EKEventStore()
    @Published var events: [EKEvent] = []
    @Published var connected = false
    /// Calendars turned off in Settings (here or on another device), by calendar identifier.
    @Published private(set) var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? [])
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
    /// Every calendar on the iPhone, grouped by account, for the per-calendar switches in Settings.
    var calendars: [EKCalendar] {
        guard connected else { return [] }
        return store.calendars(for: .event).sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
    }
    func isShown(_ calendar: EKCalendar) -> Bool { !hidden.contains(calendar.calendarIdentifier) }
    func setShown(_ calendar: EKCalendar, _ shown: Bool) {
        if shown { hidden.remove(calendar.calendarIdentifier) } else { hidden.insert(calendar.calendarIdentifier) }
        UserDefaults.standard.set(Array(hidden), forKey: "hiddenCalendars")
        reload()
    }
    /// The calendars Orbit shows; nil when every calendar is off.
    private var shownCalendars: [EKCalendar]? {
        let shown = store.calendars(for: .event).filter(isShown)
        return shown.isEmpty ? nil : shown
    }
    func reload() {
        connected = UserDefaults.standard.bool(forKey: "calendarConnected") && EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard connected else { events = []; return }
        let start = Calendar.current.startOfDay(for: .now), end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        events = events(from: start, to: end)
    }
    func events(on day: Date) -> [EKEvent] {
        guard connected else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return events(from: start, to: end)
    }
    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard connected, let calendars = shownCalendars else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars)).sorted { $0.startDate < $1.startDate }
    }
    func conflictTitles(start: Date, duration: Int, excluding id: UUID?, tasks: [PlannerTask]) -> [String] {
        let end = start.addingTimeInterval(Double(duration) * 60)
        let ownEvent = id.flatMap { UserDefaults.standard.string(forKey: "calendarEvent." + $0.uuidString) }
        let calendarConflicts = events(from: start, to: end).filter { !$0.isAllDay && $0.availability != .free && $0.eventIdentifier != ownEvent }.map { $0.title ?? "Calendar event" }
        let taskConflicts = tasks.filter { candidate in
            candidate.id != id && candidate.hasTime && candidate.completedAt == nil && candidate.dueDate.map { PlannerLogic.overlaps(start, end, $0, $0.addingTimeInterval(Double(candidate.durationMinutes) * 60)) } == true
        }.map(\.title)
        return Array(Set(calendarConflicts + taskConflicts)).sorted()
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
                if action == .saved, let taskID = parent.draft.taskID, let id = controller.event?.eventIdentifier {
                    UserDefaults.standard.set(id, forKey: "calendarEvent." + taskID.uuidString)
                }
                CalendarBridge.shared.reload(); parent.dismiss()
            }
        }
    }
}

/// A calendar event on Today. Tap opens it to view or edit; touch and hold for Edit, Show in Calendar,
/// Copy text, Add as a task and Delete event.
struct CalendarEventRow: View {
    let event: EKEvent
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var editing: CalendarDraft?
    @State private var confirmDelete = false
    @State private var message: String?
    var body: some View {
        // The row opens the event; its address is a button of its own that opens Maps (or a meeting link).
        row
            .contentShape(Rectangle())
            .onTapGesture { editing = CalendarDraft(taskID: nil, event: event) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { editing = CalendarDraft(taskID: nil, event: event) }
            .accessibilityAction(named: place.map { EventPlace.isLink($0) ? "Join Meeting" : "Open in Maps" } ?? "Copy Text") {
                if let place { open(place) } else { UIPasteboard.general.string = copyText }
            }
            .contextMenu {
                Button("Edit event", systemImage: "pencil") { editing = CalendarDraft(taskID: nil, event: event) }
                if let place {
                    Button(EventPlace.isLink(place) ? "Join Meeting" : "Open in Maps", systemImage: EventPlace.isLink(place) ? "video" : "map") { open(place) }
                    Button("Copy Address", systemImage: "mappin.and.ellipse") { UIPasteboard.general.string = event.location }
                }
                Button("Show in Calendar", systemImage: "calendar") {
                    if let url = URL(string: "calshow:\(event.startDate.timeIntervalSinceReferenceDate)") { openURL(url) }
                }
                Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyText }
                Button("Add as a task", systemImage: "checklist") { addTask() }
                if event.calendar.allowsContentModifications {
                    Divider()
                    Button("Delete event", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
            .accessibilityHint("Opens the event. Touch and hold for more.")
            .sheet(item: $editing) { draft in CalendarEventEditor(draft: draft).ignoresSafeArea() }
            .confirmationDialog("Delete \(event.title ?? "this event")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Event", role: .destructive) { delete() }
            } message: { Text(event.hasRecurrenceRules ? "Only this occurrence is deleted." : "It is removed from \(event.calendar.title).") }
            .alert("Calendar", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
    }
    private var place: String? {
        let value = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
    private func open(_ place: String) {
        guard let url = EventPlace.url(place) else { return }
        openURL(url)
    }
    private var copyText: String {
        let when = event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened) + "–" + event.endDate.formatted(date: .omitted, time: .shortened)
        return [event.title ?? "Event", when, event.location ?? "", event.notes ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
    }
    /// A to-do for the same day (and time, for a timed event), so prep or follow-up can be ticked off.
    private func addTask() {
        let task = PlannerTask(title: event.title ?? "Event", dueDate: event.isAllDay ? Calendar.current.startOfDay(for: event.startDate) : event.startDate, hasTime: !event.isAllDay)
        if !event.isAllDay { task.durationMinutes = min(1440, max(5, Int(event.endDate.timeIntervalSince(event.startDate) / 60))) }
        context.insert(task)
        do { try Mutations.save(context) } catch { message = error.localizedDescription }
    }
    private func delete() {
        do { try CalendarBridge.shared.store.remove(event, span: .thisEvent); CalendarBridge.shared.reload() }
        catch { message = error.localizedDescription }
    }
    private var row: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Event").font(.subheadline.weight(.medium))
                Text(event.calendar.title).font(.caption).foregroundStyle(.secondary)
                if let place {
                    Button { open(place) } label: {
                        Label(EventPlace.oneLine(place), systemImage: EventPlace.isLink(place) ? "video" : "mappin.and.ellipse")
                            .font(.caption).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(EventPlace.isLink(place) ? "Opens the meeting link" : "Opens the address in Maps")
                }
                if typeSize.isAccessibilitySize { timeLabel }
            }
            if !typeSize.isAccessibilitySize { Spacer(); timeLabel }
        }.padding(12).frame(minHeight: 60).background(DayTheme.surface, in: RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous))
    }
    private var timeLabel: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                if !event.isAllDay { Text(event.endDate.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary) }
            }.font(.caption).monospacedDigit()
    }
}

/// An event's location: an address (two lines from Apple Maps, "Place\nStreet, City") or a meeting link.
enum EventPlace {
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    static func isLink(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.hasPrefix("https://") && !value.contains(" ")
    }
    /// A meeting link opens as itself; anything else searches Apple Maps.
    static func url(_ text: String) -> URL? {
        if isLink(text) { return URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        var parts = URLComponents(string: "maps://")
        parts?.queryItems = [URLQueryItem(name: "q", value: oneLine(text))]
        return parts?.url
    }
}
