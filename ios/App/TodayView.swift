import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query private var ideas: [IdeaPrompt]
    @State private var quickText = ""
    @State private var editing: PlannerTask?
    @State private var adding = false
    @State private var error: String?
    @State private var feedback = 0

    private var todayTasks: [PlannerTask] {
        tasks.filter { $0.dueDate.map { Calendar.current.isDateInToday($0) } ?? true }
    }
    private var overdue: [PlannerTask] {
        tasks.filter { $0.completedAt == nil && ($0.dueDate.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false) }
    }
    private var completed: Int { todayTasks.filter { $0.completedAt != nil }.count }
    private var habitCompleted: Int { habits.filter { PlannerLogic.progress($0, logs: logs, at: .now) >= $0.target }.count }
    private var idea: IdeaPrompt? {
        // One curated suggestion per day; reading the screen does not mutate the queue.
        let active = ideas.filter { !$0.dismissed }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard !active.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return active[day % active.count]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                            .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        Text("Today").font(.largeTitle.weight(.semibold))
                        Text("Make room for what matters.").foregroundStyle(.secondary)
                    }
                    DayCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("YOUR DAILY RHYTHM").font(.caption2.weight(.bold)).tracking(1.5)
                                Text("\(completed + habitCompleted) of \(todayTasks.count + habits.count) complete").font(.title3.weight(.medium))
                            }
                            Spacer()
                            Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(DayTheme.accent)
                        }
                        ProgressView(value: Double(completed + habitCompleted), total: Double(max(1, todayTasks.count + habits.count)))
                            .tint(DayTheme.accent)
                    }
                    HStack {
                        Image(systemName: "plus").foregroundStyle(DayTheme.accent)
                        TextField("Add a task · gym tomorrow 6am", text: $quickText).submitLabel(.done).onSubmit(quickAdd)
                        if !quickText.isEmpty { Button(action: quickAdd) { Image(systemName: "arrow.up.circle.fill") }.accessibilityLabel("Add task") }
                    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if !overdue.isEmpty {
                        taskSection("A fresh start", detail: "\(overdue.count) overdue", items: overdue)
                    }
                    taskSection("On the agenda", detail: "TIME BLOCKS", items: todayTasks.filter { $0.hasTime }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) })
                    taskSection("At your own pace", detail: "TO-DOS", items: todayTasks.filter { !$0.hasTime })
                    VStack(spacing: 12) {
                        SectionHeading(title: "Non-negotiables", detail: "\(habitCompleted)/\(habits.count)")
                        if habits.isEmpty { empty("Small steps add up. Create your first habit in Habits.") }
                        ForEach(habits) { habit in HabitRow(habit: habit, logs: logs, date: .now) }
                    }
                    if let idea {
                        DayCard {
                            Label("A LITTLE OUTSIDE THE USUAL", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(DayTheme.accent)
                            Text(idea.text).font(.title3)
                            Button("Done with this idea") {
                                idea.dismissed = true; idea.shownAt = .now; idea.updatedAt = .now
                                do { try Mutations.save(context) } catch { self.error = error.localizedDescription }
                            }.font(.caption)
                        }
                    }
                }.padding(20).frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            }
            .background(DayTheme.canvas(scheme))
            .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { adding = true } label: { Image(systemName: "plus.circle") }.accessibilityLabel("New task") }
            .sheet(isPresented: $adding) { TaskEditor() }
            .sheet(item: $editing) { TaskEditor(task: $0) }
            .modifier(MutationErrorModifier(error: $error))
            .sensoryFeedback(.success, trigger: feedback)
        }
    }
    private func empty(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
    private func taskSection(_ title: String, detail: String, items: [PlannerTask]) -> some View {
        VStack(spacing: 12) {
            SectionHeading(title: title, detail: detail)
            if items.isEmpty { empty("Nothing here. Leave some breathing room.") }
            ForEach(items) { task in
                TaskRow(task: task) { editing = task }
                    .draggable(task.id.uuidString)
                    .dropDestination(for: String.self) { ids, _ in
                        guard !task.hasTime, let id = ids.first,
                              let source = tasks.first(where: { $0.id.uuidString == id }),
                              !source.hasTime, source.id != task.id else { return false }
                        var ordered = tasks.filter { $0.id != source.id }
                        guard let index = ordered.firstIndex(where: { $0.id == task.id }) else { return false }
                        ordered.insert(source, at: index)
                        for (index, item) in ordered.enumerated() { item.sortOrder = index; item.updatedAt = .now }
                        do { try Mutations.save(context); return true } catch { self.error = error.localizedDescription; return false }
                    }
            }
        }
    }
    private func quickAdd() {
        let parsed = QuickAdd.parse(quickText)
        guard !parsed.title.isEmpty else { error = "Add a task title, for example: gym tomorrow 6am."; return }
        let task = PlannerTask(title: parsed.title, dueDate: parsed.date, hasTime: parsed.hasTime)
        task.sortOrder = (tasks.map(\.sortOrder).max() ?? -1) + 1
        context.insert(task)
        do { try Mutations.save(context); quickText = ""; feedback += 1 }
        catch { self.error = error.localizedDescription }
    }
}

struct TaskRow: View {
    @Environment(\.modelContext) private var context
    let task: PlannerTask
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    var body: some View {
        HStack(spacing: 14) {
            Button {
                do { try Mutations.toggle(task, in: context); feedback += 1
                    Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
                } catch { self.error = error.localizedDescription }
            } label: {
                Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill").font(.title2)
                    .foregroundStyle(task.completedAt == nil ? DayTheme.accent.opacity(0.55) : DayTheme.accent)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(task.completedAt == nil ? "Complete \(task.title)" : "Reopen \(task.title)")
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).strikethrough(task.completedAt != nil).foregroundStyle(task.completedAt == nil ? .primary : .secondary)
                    HStack(spacing: 8) {
                        if task.hasTime, let date = task.dueDate {
                            Text(date.formatted(date: .omitted, time: .shortened))
                            Text("· \(task.durationMinutes) min")
                        }
                        if task.priority > 0 { Image(systemName: "flag.fill").foregroundStyle(DayTheme.accent) }
                        if !task.recurrenceRule.isEmpty { Image(systemName: "repeat") }
                        if !task.subtasks.isEmpty { Text("\(task.subtasks.filter(\.completed).count)/\(task.subtasks.count)") }
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(8).background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
    }
}

struct HabitRow: View {
    @Environment(\.modelContext) private var context
    let habit: Habit
    let logs: [HabitLog]
    let date: Date
    @State private var error: String?
    @State private var feedback = 0
    private var progress: Int { PlannerLogic.progress(habit, logs: logs, at: date) }
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: habit.icon).font(.title3).foregroundStyle(DayTheme.color(habit.color))
                .frame(width: 44, height: 44).background(DayTheme.color(habit.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.title).font(.subheadline.weight(.medium))
                Text("\(progress)/\(habit.target) this \(habit.frequencyRule == "WEEKLY" ? "week" : "day") · \(PlannerLogic.streak(habit, logs: logs, at: date)) period streak")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                do { try Mutations.log(habit, at: date, in: context); feedback += 1
                    Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
                } catch { self.error = error.localizedDescription }
            } label: {
                Image(systemName: progress >= habit.target ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2).foregroundStyle(DayTheme.color(habit.color)).frame(width: 44, height: 44)
            }.buttonStyle(.plain).disabled(progress >= habit.target)
                .accessibilityLabel("Log \(habit.title), \(progress) of \(habit.target)")
        }.contextMenu {
            Button("Undo one log today", systemImage: "arrow.uturn.backward") {
                do { try Mutations.undoLog(habit, at: date, in: context)
                    Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
                } catch { self.error = error.localizedDescription }
            }
        }.modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
    }
}
