import SwiftUI
import SwiftData
import EventKit

struct CalendarView: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @ObservedObject private var calendars = CalendarBridge.shared
    @State private var selected = Date.now
    @State private var mode = "Week"
    @State private var editing: PlannerTask?
    @State private var adding = false
    @State private var error: String?
    private var calendar: Calendar { .current }
    private var days: [Date] {
        let interval = calendar.dateInterval(of: mode == "Week" ? .weekOfYear : .month, for: selected)!
        var result: [Date] = []
        var day = mode == "Month" ? calendar.dateInterval(of: .weekOfYear, for: interval.start)!.start : interval.start
        for _ in 0..<(mode == "Week" ? 7 : 42) { result.append(day); day = calendar.date(byAdding: .day, value: 1, to: day)! }
        return result
    }
    private var selectedTasks: [PlannerTask] {
        tasks.filter { $0.day == PlannerLogic.dayKey(selected) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                let visibleEvents = calendars.events(from: days[0], to: calendar.date(byAdding: .day, value: 1, to: days.last!)!)
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Calendar view", selection: $mode) { Text("Week").tag("Week"); Text("Month").tag("Month") }.pickerStyle(.segmented)
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous \(mode.lowercased())")
                        Spacer()
                        Text(selected.formatted(.dateTime.month(.wide).year())).font(.title2)
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next \(mode.lowercased())")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                        ForEach(days, id: \.self) { day in
                            Button { selected = day } label: {
                                VStack(spacing: 8) {
                                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2)
                                    Text(day.formatted(.dateTime.day())).font(.subheadline.weight(.semibold))
                                    Circle().fill((tasks.contains { $0.day == PlannerLogic.dayKey(day) } || visibleEvents.contains { $0.startDate < calendar.date(byAdding: .day, value: 1, to: day)! && $0.endDate > day }) ? DayTheme.accent : .clear).frame(width: 4, height: 4)
                                }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(calendar.isDate(day, inSameDayAs: selected) ? DayTheme.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                                .dropDestination(for: String.self) { ids, _ in reschedule(ids, to: day) }
                        }
                    }
                    SectionHeading(title: selected.formatted(.dateTime.weekday(.wide).month().day()))
                    if !calendars.connected {
                        Button("Connect Calendars", systemImage: "calendar.badge.plus") { Task { do { try await calendars.connect() } catch { self.error = error.localizedDescription } } }
                    }
                    let events = calendars.events(on: selected)
                    if selectedTasks.isEmpty && events.isEmpty { ContentUnavailableView("Nothing Planned", systemImage: "sun.horizon") }
                    ForEach(events.filter(\.isAllDay), id: \.calendarItemIdentifier) { event in CalendarEventRow(event: event) }
                    ForEach(selectedTasks.filter { !$0.hasTime }) { task in TaskRow(task: task) { editing = task }.draggable(task.id.uuidString) }
                    ForEach(timeline(events), id: \.id) { entry in
                        if let task = entry.task { TaskRow(task: task) { editing = task }.draggable(task.id.uuidString) }
                        if let event = entry.event { CalendarEventRow(event: event) }
                    }
                    Text("Drag a task onto a day to move it.").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(DayTheme.canvas(scheme)).tint(DayTheme.accentColor(accentTheme)).navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Today") { selected = .now } }
                    ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("New task") }
                }
                .sheet(item: $editing) { TaskEditor(task: $0) }
                .sheet(isPresented: $adding) { QuickCapture(initialDate: selected) }
                .modifier(MutationErrorModifier(error: $error))
        }
    }
    private struct Entry: Identifiable {
        let id: String
        let date: Date
        var task: PlannerTask? = nil
        var event: EKEvent? = nil
    }
    private func timeline(_ events: [EKEvent]) -> [Entry] {
        (selectedTasks.filter(\.hasTime).map { Entry(id: $0.id.uuidString, date: $0.dueDate ?? selected, task: $0) } + events.filter { !$0.isAllDay }.map { Entry(id: $0.calendarItemIdentifier, date: $0.startDate, event: $0) }).sorted { $0.date < $1.date }
    }
    private func move(_ amount: Int) { selected = calendar.date(byAdding: mode == "Week" ? .weekOfYear : .month, value: amount, to: selected)! }
    private func reschedule(_ ids: [String], to day: Date) -> Bool {
        guard let id = ids.first, let task = tasks.first(where: { $0.id.uuidString == id }) else { return false }
        let old = task.dueDate
        let time = calendar.dateComponents([.hour, .minute], from: old ?? day)
        let new = calendar.date(bySettingHour: task.hasTime ? time.hour! : 0, minute: task.hasTime ? time.minute! : 0, second: 0, of: day)!
        task.schedule(new, hasTime: task.hasTime); task.updatedAt = .now
        if let old { task.reminders = task.reminders.map { new.addingTimeInterval($0.timeIntervalSince(old)) } }
        do { try Mutations.save(context)
            Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
