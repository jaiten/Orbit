import SwiftUI
import SwiftData
import EventKit

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query private var ideas: [IdeaPrompt]
    @State private var editing: PlannerTask?
    @State private var editingHabit: Habit?
    @State private var addingTask = false
    @State private var addingHabit = false
    @State private var customizing = false
    @AppStorage("homeSections") private var homeSections = "consistency,today,routine,completed,calendar"
    @AppStorage("hiddenHomeSections") private var hiddenSections = ""
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var completedExpanded = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 150
    @State private var contentWidth: CGFloat = 0
    @State private var error: String?
    @State private var day = Calendar.current.startOfDay(for: .now)
    @ObservedObject private var calendars = CalendarBridge.shared
    @ObservedObject private var focus = FocusSession.shared
    private var relevant: [PlannerTask] {
        tasks.filter { $0.dueDate.map { $0 < Calendar.current.date(byAdding: .day, value: 1, to: day)! } ?? true }
            .filter { $0.completedAt == nil || $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } == true }
    }
    private var done: Int { relevant.filter { $0.completedAt != nil }.count + habits.filter { PlannerLogic.progress($0, logs: logs, at: day) >= $0.target }.count }
    private var total: Int { relevant.count + habits.count }
    private var idea: IdeaPrompt? {
        let active = ideas.filter { !$0.dismissed }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard !active.isEmpty else { return nil }
        let index = Calendar.current.ordinality(of: .day, in: .era, for: day) ?? 0
        return active[index % active.count]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                Group {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(done)/\(total)").monospacedDigit().foregroundStyle(.secondary)
                        }.font(.caption)
                        ProgressView(value: Double(done), total: Double(max(1, total))).tint(DayTheme.accent)
                    }.padding(.vertical, 4)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                if let title = focus.title, let end = focus.endsAt {
                    Section {
                        HStack {
                            Image(systemName: "timer").foregroundStyle(DayTheme.accent)
                            Text(title).lineLimit(1)
                            Spacer()
                            if end > .now { Text(timerInterval: focus.startedAt...end, countsDown: true).monospacedDigit().frame(width: 70) }
                            else { Text("Finished").font(.caption) }
                            Button("Stop") { Task { await focus.stop() } }.font(.caption)
                        }
                    }
                }
                ForEach(homeSections.split(separator: ",").map(String.init).filter { !hiddenSections.split(separator: ",").contains(Substring($0)) }, id: \.self) { section in
                    homeSection(section)
                }
                }
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { contentWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in contentWidth = width }
                })
                .padding(.horizontal, 20).padding(.bottom, 16).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }

            .background(DayTheme.canvas(scheme))
            .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { customizing = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Edit Today") }; ToolbarItem(placement: .topBarTrailing) { SyncIndicator() } }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                Button { addingTask = true } label: {
                    Image(systemName: "plus").font(.title2.weight(.medium)).foregroundStyle(.white)
                        .frame(width: 54, height: 54).background(DayTheme.accent, in: Circle())
                        .shadow(color: .black.opacity(0.13), radius: 10, y: 4)
                }.accessibilityLabel("Add something").padding(.trailing, 20).padding(.bottom, 10)
            }
            .sheet(isPresented: $addingTask) { QuickCapture(initialDate: day) }
            .sheet(isPresented: $customizing) { HomeLayoutEditor() }
            .sheet(isPresented: $addingHabit) { HabitEditor() }
            .sheet(item: $editing) { TaskEditor(task: $0) }
            .sheet(item: $editingHabit) { HabitEditor(habit: $0) }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: done)
            .modifier(MutationErrorModifier(error: $error))
            .task { refresh(); while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); if !Task.isCancelled { refresh() } } }
            .onChange(of: phase) { _, value in if value == .active { refresh() } }
        }
    }
    @ViewBuilder private func homeSection(_ id: String) -> some View {
        switch id {
        case "consistency": ConsistencyStrip(habits: habits, logs: logs)
        case "today":
            checklistSection("For today", items: relevant.filter { $0.completedAt == nil && $0.recurrenceRule.isEmpty }.map { TodayItem(task: $0) }, empty: "Your one-off plans go here.")
                .dropDestination(for: String.self) { values, _ in move(values, routine: false) }
        case "routine":
            checklistSection("Your routine", items: relevant.filter { $0.completedAt == nil && !$0.recurrenceRule.isEmpty }.map { TodayItem(task: $0) } + habits.filter { PlannerLogic.progress($0, logs: logs, at: day) < $0.target }.map { TodayItem(habit: $0) }, empty: "Hold and drag a to-do here to make it a habit.")
                .dropDestination(for: String.self) { values, _ in move(values, routine: true) }
        case "completed":
            let completed = relevant.filter { $0.completedAt != nil }.map { TodayItem(task: $0) } + habits.filter { PlannerLogic.progress($0, logs: logs, at: day) >= $0.target }.map { TodayItem(habit: $0) }
            if !completed.isEmpty { DisclosureGroup("Completed · \(completed.count)", isExpanded: $completedExpanded) { checklist(completed).padding(.top, 10) }.font(.subheadline).foregroundStyle(.secondary) }
        case "calendar":
            if calendars.connected {
                VStack(alignment: .leading, spacing: 12) {
                    Text("From your calendars").font(.headline)
                    if calendars.events.isEmpty { Text("No events today").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(calendars.events, id: \.calendarItemIdentifier) { event in CalendarEventRow(event: event) }
                }
            }
        default:
            if let list = lists.first(where: { "list:" + $0.id.uuidString == id }) {
                checklistSection(list.name, items: tasks.filter { $0.listID == list.id && $0.completedAt == nil }.map { TodayItem(task: $0) }, empty: "Nothing waiting in this list.")
            }
        }
    }
    private func move(_ values: [String], routine: Bool) -> Bool {
        guard let value = values.first else { return false }
        do {
            if routine, let task = tasks.first(where: { "task:" + $0.id.uuidString == value }), task.recurrenceRule.isEmpty {
                try Conversions.toHabit(task, in: context)
            } else if !routine, let habit = habits.first(where: { "habit:" + $0.id.uuidString == value }) {
                try Conversions.toTask(habit, in: context)
            } else if !routine, let task = tasks.first(where: { "task:" + $0.id.uuidString == value }), !task.recurrenceRule.isEmpty {
                task.recurrenceRule = ""; task.updatedAt = .now; try Mutations.save(context)
            } else { return false }
            Task { try? await refreshReminders(context) }; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func checklistSection(_ title: String, items: [TodayItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.headline); Spacer(); Text("\(items.count)").font(.caption).foregroundStyle(.tertiary) }
            if items.isEmpty { Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8) }
            checklist(items)
        }
    }
    private func checklist(_ items: [TodayItem]) -> some View {
        VStack(spacing: 10) {
            ForEach(TodayGroup.groups(items, compact: !typeSize.isAccessibilitySize && contentWidth >= tileWidth * 2 + 10)) { group in
                if group.items.count == 2 {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(group.items) { item in itemView(item).frame(maxWidth: .infinity) }
                    }
                } else { itemView(group.items[0]) }
            }
        }
    }
    @ViewBuilder private func itemView(_ item: TodayItem) -> some View {
        if let task = item.task { TaskRow(task: task) { editing = task }.draggable("task:" + task.id.uuidString) }
        if let habit = item.habit { HabitRow(habit: habit, logs: logs, date: day, edit: { editingHabit = habit }).draggable("habit:" + habit.id.uuidString) }
    }
    private func refresh() { day = Calendar.current.startOfDay(for: .now); calendars.reload(); focus.restore() }
}

struct TodayItem: Identifiable {
    var task: PlannerTask? = nil
    var habit: Habit? = nil
    var id: String { task.map { "task-" + $0.id.uuidString } ?? "habit-" + habit!.id.uuidString }
    var short: Bool { (task?.title ?? habit!.title).count <= 18 && task?.hasTime != true && (task?.subtasks.isEmpty ?? true) }
}
struct TodayGroup: Identifiable {
    let items: [TodayItem]
    var id: String { items[0].id }
    static func groups(_ items: [TodayItem], compact: Bool) -> [TodayGroup] {
        var groups: [TodayGroup] = []; var index = 0
        while index < items.count {
            if compact, items[index].short, index + 1 < items.count, items[index + 1].short {
                groups.append(TodayGroup(items: [items[index], items[index + 1]])); index += 2
            } else { groups.append(TodayGroup(items: [items[index]])); index += 1 }
        }
        return groups
    }
}

struct CheckTile: View {
    let title: String
    let subtitle: String
    let done: Bool
    let color: Color
    let completionLabel: String
    let moveLabel: String
    var toggle: () -> Void
    var edit: () -> Void
    var remove: () -> Void
    var move: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actionEdge = 0
    @State private var dragOffset: CGFloat = 0
    @State private var gestureMoved = false
    @GestureState private var gestureActive = false
    var body: some View {
        ZStack(alignment: .trailing) {
            Button { remove(); actionEdge = 0 } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 64, height: 72)
            }.buttonStyle(.plain).accessibilityLabel("Delete").opacity(actionEdge == -1 || dragOffset < 0 ? 1 : 0)
            HStack(spacing: 0) {
            Button { if !gestureMoved { if actionEdge == 0 { toggle() } else { actionEdge = 0 } } } label: {
                HStack(spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 23, weight: .regular)).foregroundStyle(done ? color : color.opacity(0.65))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.subheadline.weight(.medium)).foregroundStyle(done ? .secondary : .primary).strikethrough(done).fixedSize(horizontal: false, vertical: true)
                        if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                }.padding(.leading, 14).padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(completionLabel).accessibilityValue(subtitle).accessibilityIdentifier("checklist-title")
            Button { if !gestureMoved { edit() } } label: { Image(systemName: "pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 38, height: 54).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel("Edit " + title)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.035)))
            .offset(x: max(-76, min(0, CGFloat(actionEdge == -1 ? -70 : 0) + dragOffset)))
        }.background(Color.red, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 10)
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                gestureMoved = true
                if abs(value.translation.width) > abs(value.translation.height) * 1.4 { dragOffset = value.translation.width }
            }
            .onEnded { value in
                if abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                        actionEdge = CGFloat(actionEdge == -1 ? -70 : 0) + value.translation.width < -32 ? -1 : 0
                        dragOffset = 0
                    }
                }
            })
        .onChange(of: gestureActive) { _, active in
            if !active { dragOffset = 0; Task { try? await Task.sleep(for: .milliseconds(150)); gestureMoved = false } }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: actionEdge)
    }
}

struct TaskRow: View {
    @Environment(\.modelContext) private var context
    let task: PlannerTask
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    private var subtitle: String {
        var parts: [String] = []
        if task.hasTime, let date = task.dueDate { parts.append(date.formatted(date: .omitted, time: .shortened)) }
        if !task.recurrenceRule.isEmpty { parts.append(task.recurrenceRule.contains("BYDAY=MO") ? "Weekdays" : task.recurrenceRule.contains("BYDAY=SA") ? "Weekends" : task.recurrenceRule == "FREQ=DAILY" ? "Daily" : task.recurrenceRule == "FREQ=WEEKLY" ? "Weekly" : "Monthly") }
        if !task.subtasks.isEmpty { parts.append("\(task.subtasks.filter(\.completed).count)/\(task.subtasks.count) steps") }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        CheckTile(title: task.title, subtitle: subtitle, done: task.completedAt != nil, color: DayTheme.accent,
            completionLabel: (task.completedAt == nil ? "Complete " : "Reopen ") + task.title, moveLabel: "Make non-negotiable",
            toggle: { change { try Mutations.toggle(task, in: context); feedback += 1; if task.completedAt != nil { Task { await FocusSession.shared.stopIfMatching(task.id) } } } }, edit: edit,
            remove: { change { context.delete(task); try Mutations.save(context) } }, move: { change { try Conversions.toHabit(task, in: context) } })
            .modifier(TaskActions(task: task)).modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
    }
    private func change(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { self.error = error.localizedDescription }
    }
}

struct HabitRow: View {
    @Environment(\.modelContext) private var context
    let habit: Habit
    let logs: [HabitLog]
    let date: Date
    var edit: (() -> Void)? = nil
    @State private var error: String?
    @State private var feedback = 0
    private var progress: Int { PlannerLogic.progress(habit, logs: logs, at: date) }
    var body: some View {
        CheckTile(title: habit.title, subtitle: habit.target == 1 ? (habit.frequencyRule == "WEEKLY" ? "Weekly" : "Daily") : "\(progress)/\(habit.target) \(habit.frequencyRule == "WEEKLY" ? "this week" : "today")", done: progress >= habit.target, color: DayTheme.color(habit.color),
            completionLabel: (progress >= habit.target ? "Undo " : "Log ") + habit.title, moveLabel: "Make to-do",
            toggle: { change { if progress >= habit.target { try Mutations.undoLog(habit, at: date, in: context) } else { try Mutations.log(habit, at: date, in: context) }; feedback += 1 } }, edit: { edit?() },
            remove: { change { try Conversions.remove(habit, in: context) } }, move: { change { try Conversions.toTask(habit, in: context) } })
            .contextMenu {
                Button("Move to to-dos", systemImage: "checklist") { change { try Conversions.toTask(habit, in: context) } }
                Button("Delete", systemImage: "xmark", role: .destructive) { change { try Conversions.remove(habit, in: context) } }
            }
            .modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
    }
    private func change(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { self.error = error.localizedDescription }
    }
}
