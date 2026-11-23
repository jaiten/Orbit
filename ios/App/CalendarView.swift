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
    @AppStorage(SomedayRules.storageKey, store: SomedayRules.defaults) private var visibilityData = Data()
    @State private var selected = Date.now
    @State private var mode = "Week"
    @State private var editing: PlannerTask?
    @State private var adding = false
    @State private var overview = false
    @State private var error: String?
    @State private var showCompleted = false
    /// The day a dragged task is over, so it can show where the task will land.
    @State private var dropTarget: Date?
    @State private var dropped = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("calendarFirstWeekday") private var firstWeekday = Calendar.current.firstWeekday
    private var calendar: Calendar { var value = Calendar.current; value.firstWeekday = firstWeekday; return value }
    private var days: [Date] {
        let interval = calendar.dateInterval(of: mode == "Week" ? .weekOfYear : .month, for: selected)!
        var result: [Date] = []
        var day = mode == "Month" ? calendar.dateInterval(of: .weekOfYear, for: interval.start)!.start : interval.start
        let end = mode == "Week" ? calendar.date(byAdding: .day, value: 7, to: day)! : calendar.date(byAdding: .day, value: 6, to: interval.end)!
        while day < end {
            if mode == "Month", day >= interval.end, calendar.component(.weekday, from: day) == calendar.firstWeekday { break }
            result.append(day); day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }
    /// The chosen day's tasks, with Someday tasks whose @tag rule matches the day.
    private var selectedTasks: [PlannerTask] {
        (tasks.filter { !$0.note && $0.day == PlannerLogic.dayKey(selected) }
            + SomedayRules.tasks(tasks, on: selected, rules: SomedayRules.decode(visibilityData), bridge: calendars))
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                let visibleEvents = calendars.events(from: days[0], to: calendar.date(byAdding: .day, value: 1, to: days.last!)!)
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
                    // The month is the title; Today and + sit at the top right, as in Calendar.
                    PageHeader(eyebrow: selected.formatted(.dateTime.year()), title: selected.formatted(.dateTime.month(.wide))) {
                        Button { selected = .now } label: { Text("Today").font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44).fixedSize(horizontal: true, vertical: false) }
                        Button { adding = true } label: { Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44) }
                            .accessibilityLabel("Add task for " + selected.formatted(.dateTime.month(.abbreviated).day()))
                            .accessibilityIdentifier("calendar-add-task")
                    }
                    HStack(spacing: 4) {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44) }.accessibilityLabel("Previous \(mode.lowercased())")
                        Picker("Calendar view", selection: $mode) { Text("Week").tag("Week"); Text("Month").tag("Month") }.pickerStyle(.segmented)
                        Button { move(1) } label: { Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44) }.accessibilityLabel("Next \(mode.lowercased())")
                    }
                    if typeSize.isAccessibilitySize {
                        DatePicker("Selected day", selection: $selected, displayedComponents: .date)
                    } else {
                        VStack(spacing: 4) {
                            if mode == "Month" {
                                HStack(spacing: 4) {
                                    ForEach(Array(days.prefix(7)), id: \.self) { day in
                                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                                ForEach(days, id: \.self) { day in
                                    Button { selected = day } label: { dayCell(day, events: visibleEvents) }
                                        .buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                                        .dropDestination(for: String.self) { ids, _ in reschedule(ids, to: day) } isTargeted: { over in
                                            if over { dropTarget = day } else if dropTarget == day { dropTarget = nil }
                                        }
                                }
                            }
                        }
                    }
                    let linked = Set(selectedTasks.filter(\.hasTime).compactMap { UserDefaults.standard.string(forKey: "calendarEvent." + $0.id.uuidString) })
                    let events = calendars.events(on: selected).filter { !linked.contains($0.eventIdentifier ?? "") }
                    let agenda = agendaEntries(events)
                    SectionLabel(title: selected.formatted(.dateTime.weekday(.wide).month().day()),
                                 note: calendar.isDateInToday(selected) ? "Today" : agenda.isEmpty ? "" : "\(agenda.count) \(agenda.count == 1 ? "item" : "items")")
                    if !calendars.connected {
                        Button("Connect Calendars", systemImage: "calendar.badge.plus") { Task { do { try await calendars.connect() } catch { self.error = error.localizedDescription } } }
                    }
                    if selectedTasks.isEmpty && events.isEmpty { ContentUnavailableView("Nothing Planned", systemImage: "sun.horizon") }
                    // The day's events and tasks in one grouped card, all-day items first, then by time.
                    if !agenda.isEmpty {
                        GroupedRows {
                            ForEach(Array(agenda.enumerated()), id: \.element.id) { index, entry in
                                VStack(spacing: 0) {
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    // Dragging lifts a small card with the task's name, not a see-through row.
                                    if let task = entry.task { TaskRow(task: task) { editing = task }.equatable().draggable(task.id.uuidString) { DragChip(title: task.title) } }
                                    if let event = entry.event { CalendarEventRow(event: event) }
                                }.transition(.orbitRow)
                            }
                        }.animation(reduceMotion ? nil : .orbitFold, value: agenda.map(\.id))
                    }
                    let completed = selectedTasks.filter { $0.completedAt != nil }
                    if !completed.isEmpty {
                        DisclosureGroup(isExpanded: $showCompleted) {
                            GroupedRows {
                                ForEach(Array(completed.enumerated()), id: \.element.id) { index, task in
                                    if index > 0 { Divider().padding(.leading, 56) }
                                    TaskRow(task: task) { editing = task }.equatable()
                                }
                            }.padding(.top, 8)
                        } label: { Text("Completed (\(completed.count))").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Text("Choose a day, then tap +. You can also drag a task onto another day.").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS)).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(DayTheme.canvas(scheme)).tint(accent.fill).navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .onChange(of: selected) { _, _ in showCompleted = false }
                .sheet(item: $editing) { TaskEditor(task: $0).presentationDragIndicator(.visible) }
                .sheet(isPresented: $adding) { QuickCapture(initialDate: selected).presentationDragIndicator(.visible) }
                .sheet(isPresented: $overview) { AgendaSheet(day: selected).presentationDragIndicator(.visible) }
                .modifier(MutationErrorModifier(error: $error))
                .sensoryFeedback(.impact(weight: .medium), trigger: dropped)
        }
    }
    /// A day in the strip: weekday letter (week view), the date in a circle (filled when chosen, accent
    /// text for today) and a dot when anything is planned.
    @ViewBuilder private func dayCell(_ day: Date, events: [EKEvent]) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let outside = mode == "Month" && !calendar.isDate(day, equalTo: selected, toGranularity: .month)
        let busy = tasks.contains { $0.day == PlannerLogic.dayKey(day) } || events.contains { $0.startDate < calendar.date(byAdding: .day, value: 1, to: day)! && $0.endDate > day }
        let targeted = dropTarget == day
        VStack(spacing: 5) {
            if mode == "Week" {
                Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(day.formatted(.dateTime.day())).font(.body.weight(isSelected || isToday ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : isToday ? accent.text : outside ? Color.secondary.opacity(0.45) : Color.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(isSelected ? accent.text : Color.clear))
                // A task dragged over the day rings it and lifts it a little.
                .overlay(Circle().strokeBorder(accent.fill, lineWidth: 2).opacity(targeted ? 1 : 0))
                .scaleEffect(targeted ? 1.12 : 1)
            Circle().fill(busy ? accent.fill : Color.clear).frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 2).contentShape(Rectangle())
        .animation(.orbit, value: isSelected)
        .animation(reduceMotion ? nil : .orbitLift, value: targeted)
    }
    /// All-day events, then tasks without a time, then timed tasks and events in order.
    private func agendaEntries(_ events: [EKEvent]) -> [Entry] {
        let allDay: [Entry] = events.filter(\.isAllDay).map { Entry(id: $0.calendarItemIdentifier, date: selected, event: $0) }
        let untimed: [Entry] = selectedTasks.filter { !$0.hasTime && $0.completedAt == nil }.map { Entry(id: $0.id.uuidString, date: selected, task: $0) }
        return allDay + untimed + timeline(events)
    }
    private struct Entry: Identifiable {
        let id: String
        let date: Date
        var task: PlannerTask? = nil
        var event: EKEvent? = nil
    }
    private func timeline(_ events: [EKEvent]) -> [Entry] {
        (selectedTasks.filter { $0.hasTime && $0.completedAt == nil }.map { Entry(id: $0.id.uuidString, date: $0.dueDate ?? selected, task: $0) } + events.filter { !$0.isAllDay }.map { Entry(id: $0.calendarItemIdentifier, date: $0.startDate, event: $0) }).sorted { $0.date < $1.date }
    }
    private func move(_ amount: Int) { selected = calendar.date(byAdding: mode == "Week" ? .weekOfYear : .month, value: amount, to: selected)! }
    private func reschedule(_ ids: [String], to day: Date) -> Bool {
        guard let id = ids.first, let task = tasks.first(where: { $0.id.uuidString == id }) else { return false }
        let old = task.dueDate
        let time = calendar.dateComponents([.hour, .minute], from: old ?? day)
        let new = calendar.date(bySettingHour: task.hasTime ? time.hour! : 0, minute: task.hasTime ? time.minute! : 0, second: 0, of: day)!
        dropTarget = nil
        do {
            // The row leaves this day's list as its neighbours close the gap.
            try withAnimation(reduceMotion ? nil : .orbitFold) {
                task.schedule(new, hasTime: task.hasTime); task.updatedAt = .now
                if let old { task.reminders = task.reminders.map { new.addingTimeInterval($0.timeIntervalSince(old)) } }
                try Mutations.save(context)
            }
            dropped += 1
            Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

/// What follows the finger while a task is dragged to another day: a small solid card with its name.
private struct DragChip: View {
    let title: String
    var body: some View {
        Label(title, systemImage: "calendar").font(.subheadline.weight(.medium)).lineLimit(1)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: 260, alignment: .leading)
            .background(Color.orbitSurface, in: RoundedRectangle(cornerRadius: CGFloat(DesignTokens.radiusRow), style: .continuous))
    }
}
