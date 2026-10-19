import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @State private var selected = Calendar.current.startOfDay(for: Date.now)
    @State private var mode = "Week"
    @State private var editing: PlannerTask?
    @State private var adding = false
    @State private var error: String?
    @State private var feedback = 0
    private var calendar: Calendar { .current }
    private var monthDays: [Date] {
        let month = calendar.dateInterval(of: .month, for: selected)!
        let start = calendar.dateInterval(of: .weekOfYear, for: month.start)!.start
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var markedDays: Set<String> { Set(tasks.compactMap { $0.dueDate.map { PlannerLogic.dayKey($0) } }) }
    private var selectedTasks: [PlannerTask] {
        tasks.filter { $0.dueDate.map { calendar.isDate($0, inSameDayAs: selected) } ?? false }
            .sorted {
                if $0.hasTime != $1.hasTime { return !$0.hasTime }
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 12) {
                        Picker("Calendar view", selection: $mode) {
                            Text("Week").tag("Week"); Text("Month").tag("Month")
                        }.pickerStyle(.segmented)
                        HStack {
                            Text(selected.formatted(.dateTime.month(.wide).year())).font(.title3.weight(.semibold))
                            Spacer()
                            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                                .accessibilityLabel("Previous \(mode.lowercased())")
                            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                                .accessibilityLabel("Next \(mode.lowercased())")
                        }.buttonStyle(.plain)
                        if mode == "Week" {
                            WeekStrip(selection: $selected, markedDays: markedDays, onDrop: reschedule)
                        } else { monthGrid }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: calendar.isDateInToday(selected) ? "Today" : selected.formatted(.dateTime.weekday(.wide).day()),
                            detail: "\(selectedTasks.count) \(selectedTasks.count == 1 ? "task" : "tasks")")
                        if selectedTasks.isEmpty {
                            DayCard {
                                QuietEmptyState(title: "Nothing scheduled", detail: "Add a task for this day.", symbol: "calendar")
                                Button("Add task", systemImage: "plus") { adding = true }.font(.subheadline.weight(.medium))
                            }
                        }
                        if selectedTasks.contains(where: { !$0.hasTime }) {
                            DayCard {
                                Text("All day").font(.caption).foregroundStyle(.secondary)
                                VStack(spacing: 0) {
                                    ForEach(selectedTasks.filter { !$0.hasTime }) { task in
                                        TaskRow(task: task) { editing = task }.draggable(task.id.uuidString)
                                    }
                                }
                            }
                        }
                        ForEach(selectedTasks.filter(\.hasTime)) { task in
                            AgendaBlock(task: task) { editing = task }.draggable(task.id.uuidString)
                        }
                    }
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(DayTheme.canvas(scheme)).navigationTitle("Calendar")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Today") { selected = calendar.startOfDay(for: .now) } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { adding = true } label: { Image(systemName: "plus").font(.title3.weight(.medium)) }.accessibilityLabel("New task")
                    }
                }
                .sheet(item: $editing) { TaskEditor(task: $0).presentationDragIndicator(.visible) }
                .sheet(isPresented: $adding) { TaskEditor(initialDate: selected).presentationDragIndicator(.visible) }
                .modifier(MutationErrorModifier(error: $error))
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: mode)
                .sensoryFeedback(.selection, trigger: feedback)
        }
    }
    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(Array(monthDays.prefix(7).enumerated()), id: \.offset) { _, day in
                Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary).padding(.bottom, 6)
            }
            ForEach(monthDays, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                let inMonth = calendar.isDate(day, equalTo: selected, toGranularity: .month)
                Button { selected = day; feedback += 1 } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.day())).font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? DayTheme.onAccent : (calendar.isDateInToday(day) ? DayTheme.accent : Color.primary))
                            .frame(width: 32, height: 32)
                            .background(isSelected ? DayTheme.accent : .clear, in: Circle())
                        Circle().fill(markedDays.contains(PlannerLogic.dayKey(day)) ? DayTheme.accent : .clear).frame(width: 4, height: 4)
                    }.opacity(inMonth ? 1 : 0.45).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .dropDestination(for: String.self) { ids, _ in reschedule(ids, to: day) }
            }
        }
    }
    private func move(_ amount: Int) {
        selected = calendar.date(byAdding: mode == "Week" ? .weekOfYear : .month, value: amount, to: selected)!
    }
    private func reschedule(_ ids: [String], to day: Date) -> Bool {
        guard let id = ids.first, let task = tasks.first(where: { $0.id.uuidString == id }) else { return false }
        let old = task.dueDate
        let time = calendar.dateComponents([.hour, .minute], from: old ?? day)
        let new = calendar.date(bySettingHour: task.hasTime ? time.hour! : 0, minute: task.hasTime ? time.minute! : 0, second: 0, of: day)!
        task.dueDate = new; task.updatedAt = .now
        if let old { task.reminders = task.reminders.map { new.addingTimeInterval($0.timeIntervalSince(old)) } }
        do {
            try Mutations.save(context); feedback += 1
            Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

struct AgendaBlock: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let task: PlannerTask
    var edit: () -> Void
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            if let start = task.dueDate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(start.formatted(date: .omitted, time: .shortened)).font(.caption.weight(.medium)).foregroundStyle(.primary)
                    Text(start.addingTimeInterval(Double(task.durationMinutes) * 60).formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }.monospacedDigit().frame(minWidth: 64, alignment: .leading).padding(.top, 10)
            }
            HStack(spacing: 0) {
                Capsule().fill(task.completedAt == nil ? DayTheme.accent : Color.secondary.opacity(0.35)).frame(width: 3)
                TaskRow(task: task, showTime: false, edit: edit).padding(.horizontal, 8)
            }.fixedSize(horizontal: false, vertical: true)
                .background(DayTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
