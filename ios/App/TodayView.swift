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
    @State private var completedExpanded = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileWidth = 150.0
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
                VStack(alignment: .leading, spacing: 24) {
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
                checklistSection("For today", items: relevant.filter { $0.completedAt == nil && $0.recurrenceRule.isEmpty }.map { TodayItem(task: $0) }, empty: "Your one-off plans go here.")
                checklistSection("Your routine", items: relevant.filter { $0.completedAt == nil && !$0.recurrenceRule.isEmpty }.map { TodayItem(task: $0) } + habits.filter { PlannerLogic.progress($0, logs: logs, at: day) < $0.target }.map { TodayItem(habit: $0) }, empty: "Daily habits and weekly commitments.")
                let completed = relevant.filter { $0.completedAt != nil }.map { TodayItem(task: $0) } + habits.filter { PlannerLogic.progress($0, logs: logs, at: day) >= $0.target }.map { TodayItem(habit: $0) }
                if !completed.isEmpty {
                    DisclosureGroup("Completed · \(completed.count)", isExpanded: $completedExpanded) {
                        checklist(completed).padding(.top, 10)
                    }.font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                }
                if calendars.connected {
                    Section("From your calendars") {
                        if calendars.events.isEmpty { Text("No events today").foregroundStyle(.secondary) }
                        ForEach(calendars.events, id: \.calendarItemIdentifier) { event in
                            HStack {
                                RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title ?? "Event").font(.subheadline)
                                    Text(event.calendar.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                if let idea {
                    Section("A little outside the usual") {
                        Text(idea.text)
                        Button("Done with this idea") {
                            idea.dismissed = true; idea.shownAt = .now; idea.updatedAt = .now
                            do { try Mutations.save(context) } catch { self.error = error.localizedDescription }
                        }.font(.caption)
                    }
                }
                }.padding(.horizontal, 20).padding(.bottom, 16).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }

            .background(DayTheme.canvas(scheme))
            .navigationTitle("Today").navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SyncIndicator() } }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                Menu {
                    Button("To-do", systemImage: "checklist") { addingTask = true }
                    Button("Non-negotiable", systemImage: "repeat") { addingHabit = true }
                } label: {
                    Image(systemName: "plus").font(.title2.weight(.medium)).foregroundStyle(.white)
                        .frame(width: 54, height: 54).background(DayTheme.accent, in: Circle())
                        .shadow(color: .black.opacity(0.13), radius: 10, y: 4)
                }.accessibilityLabel("Add to-do or non-negotiable").padding(.trailing, 20).padding(.bottom, 10)
            }
            .sheet(isPresented: $addingTask) { TaskEditor(initialDate: day) }
            .sheet(isPresented: $addingHabit) { HabitEditor() }
            .sheet(item: $editing) { TaskEditor(task: $0) }
            .sheet(item: $editingHabit) { HabitEditor(habit: $0) }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: done)
            .modifier(MutationErrorModifier(error: $error))
            .task { refresh(); while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); if !Task.isCancelled { refresh() } } }
            .onChange(of: phase) { _, value in if value == .active { refresh() } }
        }
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
            ForEach(TodayGroup.groups(items, compact: !typeSize.isAccessibilitySize)) { group in
                if group.items.count == 2 {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(group.items) { item in itemView(item).frame(minWidth: tileWidth, maxWidth: .infinity) }
                        }
                        VStack(spacing: 10) { ForEach(group.items) { item in itemView(item) } }
                    }
                } else { itemView(group.items[0]) }
            }
        }
    }
    @ViewBuilder private func itemView(_ item: TodayItem) -> some View {
        if let task = item.task { TaskRow(task: task) { editing = task } }
        if let habit = item.habit { HabitRow(habit: habit, logs: logs, date: day, edit: { editingHabit = habit }) }
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
    @State private var gestureMoved = false
    var body: some View {
        HStack(spacing: 0) {
            Button { if !gestureMoved { toggle() } } label: {
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
            if actionEdge == 0 {
                Button { if !gestureMoved { edit() } } label: { Image(systemName: "pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 38, height: 54).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Edit " + title)
            } else {
                Button {
                    if actionEdge < 0 { remove() } else { move() }
                    actionEdge = 0
                } label: {
                    Image(systemName: actionEdge < 0 ? "xmark" : "arrow.left.arrow.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 50)
                        .background(actionEdge < 0 ? Color.red : color, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel(actionEdge < 0 ? "Delete" : moveLabel).padding(.horizontal, 8)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.035)))
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 10)
            .onChanged { _ in gestureMoved = true }
            .onEnded { value in
                if abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                    if value.translation.width < -36 { actionEdge = -1 }
                    else if value.translation.width > 36 { actionEdge = 1 }
                }
                Task { try? await Task.sleep(for: .milliseconds(150)); gestureMoved = false }
            })
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
        if !task.recurrenceRule.isEmpty { parts.append(task.recurrenceRule == "FREQ=DAILY" ? "Daily" : task.recurrenceRule == "FREQ=WEEKLY" ? "Weekly" : "Monthly") }
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
