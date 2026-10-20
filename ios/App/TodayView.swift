import SwiftUI
import SwiftData
import EventKit

struct TodayView: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @State private var editing: PlannerTask?
    @State private var editingHabit: Habit?
    @State private var addingTask = false
    @State private var customizing = false
    @State private var reviewing = false
    @AppStorage("homeSections") private var homeSections = "consistency,progress,today,routine,completed,calendar"
    @AppStorage("hiddenHomeSections") private var hiddenSections = ""
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var completedExpanded = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 150
    @State private var contentWidth: CGFloat = 0
    @State private var error: String?
    @State private var day = Calendar.current.startOfDay(for: .now)
    @ObservedObject private var homeDrag = HomeDrag.shared
    @ObservedObject private var calendars = CalendarBridge.shared
    @ObservedObject private var focus = FocusSession.shared
    /// Dated today or earlier and still open, or finished today. Undated and Someday items stay in Lists.
    private var relevant: [PlannerTask] {
        let today = PlannerLogic.dayKey(day)
        return tasks.filter { TodayRules.onDay(TodayRules.item($0), day: today, today: today) }
    }
    /// Habits scheduled for the day; a weekly habit drops off once its week is done.
    private var dueHabits: [Habit] { habits.filter { PlannerLogic.isDue($0, logs: logs, at: day) } }
    private var done: Int { relevant.filter { $0.completedAt != nil }.count + dueHabits.filter { PlannerLogic.checkedToday($0, logs: logs, at: day) }.count }
    private var total: Int { relevant.count + dueHabits.count }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
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
                    homeSection(section).zIndex(homeDrag.source == section ? 100 : 0)
                }
                }
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { contentWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in contentWidth = width }
                })
                .padding(.horizontal, 20).padding(.bottom, 16).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }

            .scrollDisabled(homeDrag.item != nil)
            .onPreferenceChange(HomeDropFrames.self) { homeDrag.frames = $0 }
            .onAppear { homeDrag.accept = { id, routine in _ = move([id], routine: routine) } }
            .onDisappear { homeDrag.reset(); homeDrag.accept = nil }
            .background(DayTheme.canvas(scheme)).tint(DayTheme.accentColor(accentTheme))
            .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { customizing = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Edit Today") }; ToolbarItem(placement: .topBarTrailing) { HStack { Button { reviewing = true } label: { Image(systemName: "moon") }.accessibilityLabel("Evening review"); SyncIndicator() } } }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                Button { addingTask = true } label: {
                    Image(systemName: "plus").font(.title2.weight(.medium)).foregroundStyle(.white)
                        .frame(width: 54, height: 54).background(DayTheme.accent, in: Circle())
                        .shadow(color: .black.opacity(0.13), radius: 10, y: 4)
                }.accessibilityLabel("Add").padding(.trailing, 20).padding(.bottom, 10)
            }
            .sheet(isPresented: $addingTask) { QuickCapture(initialDate: day) }
            .sheet(isPresented: $reviewing) { EveningReview() }
            .sheet(isPresented: $customizing) { HomeLayoutEditor() }
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
        case "progress":
            HStack(spacing: 14) {
                Text("\(done) of \(total) complete").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(max(1, total))).tint(DayTheme.accent).frame(maxWidth: 130)
            }
        case "today":
            checklistSection("Tasks", items: relevant.filter { $0.completedAt == nil }.map { TodayItem(task: $0) }, empty: "Nothing planned for today.")
                .modifier(HomeDropArea(id: "today"))
        case "routine":
            checklistSection("Habits", items: dueHabits.filter { !PlannerLogic.checkedToday($0, logs: logs, at: day) }.map { TodayItem(habit: $0) }, empty: "Hold and drag a to-do here to make it a habit.")
                .modifier(HomeDropArea(id: "routine"))
        case "completed":
            let completed = relevant.filter { $0.completedAt != nil }.map { TodayItem(task: $0) } + dueHabits.filter { PlannerLogic.checkedToday($0, logs: logs, at: day) }.map { TodayItem(habit: $0) }
            if !completed.isEmpty { DisclosureGroup("Completed · \(completed.count)", isExpanded: $completedExpanded) { checklist(completed).padding(.top, 10) }.font(.subheadline).foregroundStyle(.secondary) }
        case "calendar":
            if calendars.connected {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Calendar").font(.headline)
                    if calendars.events.isEmpty { Text("No events today").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(calendars.events, id: \.calendarItemIdentifier) { event in CalendarEventRow(event: event) }
                }
            }
        default:
            if let list = lists.first(where: { "list:" + $0.id.uuidString == id }) {
                checklistSection(list.name, items: tasks.filter { $0.listID == list.id && $0.completedAt == nil }.map { TodayItem(task: $0) }, empty: "No tasks.")
            }
        }
    }
    private func move(_ values: [String], routine: Bool) -> Bool {
        guard let value = values.first else { return false }
        do {
            if routine, let task = tasks.first(where: { "task:" + $0.id.uuidString == value }) {
                try Conversions.toHabit(task, in: context)
            } else if !routine, let habit = habits.first(where: { "habit:" + $0.id.uuidString == value }) {
                try Conversions.toTask(habit, in: context)
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
        if let task = item.task { TaskRow(task: task, dragEnabled: true, showMoves: true) { editing = task }.modifier(HomeDragSource(id: "task:" + task.id.uuidString)) }
        if let habit = item.habit { HabitRow(habit: habit, logs: logs, date: day, edit: { editingHabit = habit }).modifier(HomeDragSource(id: "habit:" + habit.id.uuidString)) }
    }
    private func refresh() { day = Calendar.current.startOfDay(for: .now); calendars.reload(); focus.restore() }
}

struct TodayItem: Identifiable {
    var task: PlannerTask? = nil
    var habit: Habit? = nil
    var id: String { task.map { "task-" + $0.id.uuidString } ?? "habit-" + habit!.id.uuidString }
    var short: Bool { let title = task?.title ?? habit!.title; return title.count <= 18 && title.split(separator: " ").allSatisfy { $0.count <= 10 } && task?.hasTime != true && (task?.subtasks.isEmpty ?? true) }
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
    var moves: [TileMove] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var homeDrag = HomeDrag.shared
    @State private var actionEdge = 0
    @State private var dragOffset: CGFloat = 0
    @State private var gestureMoved = false
    @GestureState private var gestureActive = false
    var body: some View {
        ZStack(alignment: .trailing) {
            Button { remove(); actionEdge = 0 } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 64, height: 72)
            }.buttonStyle(.plain).accessibilityLabel("Delete").accessibilityHidden(actionEdge != -1 && dragOffset >= 0).opacity(actionEdge == -1 || dragOffset < 0 ? 1 : 0)
            HStack(spacing: 0) {
            Button { if !gestureMoved && homeDrag.item == nil { if actionEdge == 0 { toggle() } else { actionEdge = 0 } } } label: {
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
            if !moves.isEmpty {
                Menu { ForEach(moves, id: \.title) { Button($0.title, action: $0.action) } } label: {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).frame(width: 34, height: 54).contentShape(Rectangle())
                }.accessibilityLabel("Move " + title)
            }
            Button { if !gestureMoved { edit() } } label: { Image(systemName: "pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 38, height: 54).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel("Edit " + title)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.035)))
            .offset(x: max(-76, min(0, CGFloat(actionEdge == -1 ? -70 : 0) + dragOffset)))
        }.background(actionEdge == -1 || dragOffset < 0 ? Color.red : Color.clear, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 10)
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                gestureMoved = true
                if homeDrag.item == nil && abs(value.translation.width) > abs(value.translation.height) * 1.4 { dragOffset = value.translation.width }
            }
            .onEnded { value in
                if homeDrag.item == nil && abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                        actionEdge = CGFloat(actionEdge == -1 ? -70 : 0) + value.translation.width < -32 ? -1 : 0
                        dragOffset = 0
                    }
                }
            })
        .onChange(of: gestureActive) { _, active in
            if !active { dragOffset = 0; Task { try? await Task.sleep(for: .milliseconds(150)); gestureMoved = false } }
        }
        .onChange(of: homeDrag.item) { _, value in if value != nil { actionEdge = 0; dragOffset = 0; gestureMoved = true } }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: actionEdge)
    }
}

struct TileMove { let title: String; let action: () -> Void }

struct TaskRow: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @Environment(\.modelContext) private var context
    let task: PlannerTask
    var dragEnabled = false
    /// Overdue tasks on Today offer Today / Later / Someday.
    var showMoves = false
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    private var overdue: Bool { showMoves && TodayRules.isOverdue(TodayRules.item(task), today: PlannerLogic.dayKey(.now)) }
    private var moves: [TileMove] {
        guard overdue else { return [] }
        return [TileMove(title: "Today") { change { TodayRules.moveToDay(task, day: .now); try Mutations.save(context) } },
                TileMove(title: "Later") { change { TodayRules.moveLater(task); try Mutations.save(context) } },
                TileMove(title: "Someday") { change { try TodayRules.moveToSomeday(task, in: context); try Mutations.save(context) } }]
    }
    private var subtitle: String {
        var parts: [String] = []
        if overdue, let day = task.day { parts.append(TodayRules.overdueLabel(day, today: PlannerLogic.dayKey(.now))) }
        if task.hasTime, let date = task.dueDate { parts.append(date.formatted(date: .omitted, time: .shortened)) }
        if !task.subtasks.isEmpty { parts.append("\(task.subtasks.filter(\.completed).count)/\(task.subtasks.count) steps") }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        CheckTile(title: task.title, subtitle: subtitle, done: task.completedAt != nil, color: DayTheme.accentColor(accentTheme),
            completionLabel: (task.completedAt == nil ? "Complete " : "Reopen ") + task.title, moveLabel: "Make It a Habit",
            toggle: { change { try Mutations.toggle(task, in: context); feedback += 1; if task.completedAt != nil { Task { await FocusSession.shared.stopIfMatching(task.id) } } } }, edit: edit,
            remove: { change { context.delete(task); try Mutations.save(context) } }, move: { change { try Conversions.toHabit(task, in: context) } }, moves: moves)
            .modifier(TaskActions(task: task, enabled: !dragEnabled)).modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
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
    private var checked: Bool { PlannerLogic.checkedToday(habit, logs: logs, at: date) }
    var body: some View {
        CheckTile(title: habit.title, subtitle: PlannerLogic.detail(habit, logs: logs, at: date), done: checked, color: DayTheme.color(habit.color),
            completionLabel: (checked ? "Undo " : "Log ") + habit.title, moveLabel: "Make It a Task",
            toggle: { change { if checked { try Mutations.undoLog(habit, at: date, in: context) } else { try Mutations.log(habit, at: date, in: context) }; feedback += 1 } }, edit: { edit?() },
            remove: { change { try Conversions.remove(habit, in: context) } }, move: { change { try Conversions.toTask(habit, in: context) } })
            .modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
    }
    private func change(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { self.error = error.localizedDescription }
    }
}
