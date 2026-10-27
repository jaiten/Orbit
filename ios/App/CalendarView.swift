import SwiftUI
import SwiftData
import EventKit

struct CalendarView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @ObservedObject private var calendars = CalendarBridge.shared
    @State private var selected = Date.now
    @State private var mode = "Week"
    @State private var editing: PlannerTask?
    @State private var adding = false
    @State private var overview = false
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
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
                    PageHeader(eyebrow: "Plan ahead", title: "Calendar") {
                        Button { overview = true } label: { Image(systemName: "list.bullet.rectangle").font(.system(size: 19)).frame(width: 44, height: 44) }
                            .accessibilityLabel("Overview").accessibilityHint("Every task and habit this week, this month or overall")
                        Button { selected = .now } label: { Text("Today").padding(.horizontal, 14).frame(minHeight: 44) }
                        Button { adding = true } label: { Image(systemName: "plus").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel("New task")
                    }
                    Picker("Calendar view", selection: $mode) { Text("Week").tag("Week"); Text("Month").tag("Month") }.pickerStyle(.segmented)
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 18)).frame(width: 44, height: 44) }.accessibilityLabel("Previous \(mode.lowercased())")
                        Spacer()
                        Text(selected.formatted(.dateTime.month(.wide).year())).font(.title2)
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "chevron.right").font(.system(size: 18)).frame(width: 44, height: 44) }.accessibilityLabel("Next \(mode.lowercased())")
                    }
                    if typeSize.isAccessibilitySize {
                        DatePicker("Selected day", selection: $selected, displayedComponents: .date)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                            ForEach(days, id: \.self) { day in
                                Button { selected = day } label: {
                                    let isSelected = calendar.isDate(day, inSameDayAs: selected)
                                    let busy = tasks.contains { $0.day == PlannerLogic.dayKey(day) } || visibleEvents.contains { $0.startDate < calendar.date(byAdding: .day, value: 1, to: day)! && $0.endDate > day }
                                    // Day tiles as on the website: surface with a line; the selected day is filled.
                                    VStack(spacing: 6) {
                                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).opacity(0.75)
                                        Text(day.formatted(.dateTime.day())).font(.subheadline.weight(.semibold)).monospacedDigit()
                                        Circle().fill(busy ? (isSelected ? Color.white : accent.fill) : .clear).frame(width: 4, height: 4)
                                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .foregroundStyle(isSelected ? Color.white : .primary)
                                        .background(isSelected ? accent.text : Color.orbitSurface, in: RoundedRectangle(cornerRadius: CGFloat(DesignTokens.radiusRow), style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: CGFloat(DesignTokens.radiusRow), style: .continuous).strokeBorder(isSelected ? .clear : Color.orbitLine))
                                        .animation(.orbit, value: isSelected)
                                }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                                    .dropDestination(for: String.self) { ids, _ in reschedule(ids, to: day) }
                            }
                        }
                    }
                    SectionLabel(title: selected.formatted(.dateTime.weekday(.wide).month().day()), note: calendar.isDateInToday(selected) ? "Today" : "")
                    Button("Add task for " + selected.formatted(.dateTime.month(.abbreviated).day()), systemImage: "plus.circle.fill") { adding = true }
                        .frame(minHeight: 44).accessibilityIdentifier("calendar-add-task")
                    if !calendars.connected {
                        Button("Connect Calendars", systemImage: "calendar.badge.plus") { Task { do { try await calendars.connect() } catch { self.error = error.localizedDescription } } }
                    }
                    let linked = Set(selectedTasks.filter(\.hasTime).compactMap { UserDefaults.standard.string(forKey: "calendarEvent." + $0.id.uuidString) })
                    let events = calendars.events(on: selected).filter { !linked.contains($0.eventIdentifier ?? "") }
                    if selectedTasks.isEmpty && events.isEmpty { ContentUnavailableView("Nothing Planned", systemImage: "sun.horizon") }
                    VStack(spacing: CGFloat(DesignTokens.spaceS)) {
                        ForEach(events.filter(\.isAllDay), id: \.calendarItemIdentifier) { event in CalendarEventRow(event: event) }
                        ForEach(selectedTasks.filter { !$0.hasTime }) { task in TaskRow(task: task) { editing = task }.draggable(task.id.uuidString) }
                        ForEach(timeline(events), id: \.id) { entry in
                            if let task = entry.task { TaskRow(task: task) { editing = task }.draggable(task.id.uuidString) }
                            if let event = entry.event { CalendarEventRow(event: event) }
                        }
                    }
                    Text("Choose a day, then tap Add task. You can also drag a task onto another day.").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS)).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(DayTheme.canvas(scheme)).tint(accent.fill).navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $editing) { TaskEditor(task: $0) }
                .sheet(isPresented: $adding) { QuickCapture(initialDate: selected) }
                .sheet(isPresented: $overview) { AgendaSheet(day: selected) }
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
