import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query private var ideas: [IdeaPrompt]
    @State private var selected = Calendar.current.startOfDay(for: Date.now)
    @State private var now = Date.now
    @State private var quickText = ""
    @State private var editing: PlannerTask?
    @State private var addingTask = false
    @State private var addingHabit = false
    @State private var showCompleted = false
    @State private var error: String?
    @State private var feedback = 0
    @FocusState private var quickFocused: Bool
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var isToday: Bool { Calendar.current.isDate(selected, inSameDayAs: now) }
    private var isFuture: Bool { Calendar.current.startOfDay(for: selected) > Calendar.current.startOfDay(for: now) }
    private var dayTasks: [PlannerTask] {
        tasks.filter { task in
            task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: selected) } ?? isToday
        }
    }
    private var scheduled: [PlannerTask] {
        dayTasks.filter { $0.hasTime && $0.completedAt == nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var overdue: [PlannerTask] {
        guard isToday else { return [] }
        return tasks.filter { $0.completedAt == nil && ($0.dueDate.map { $0 < Calendar.current.startOfDay(for: now) } ?? false) }
    }
    private var dailyHabits: [Habit] { visibleHabits.filter { $0.frequencyRule != "WEEKLY" } }
    private var weeklyHabits: [Habit] { visibleHabits.filter { $0.frequencyRule == "WEEKLY" } }
    private var visibleHabits: [Habit] {
        habits.filter { Calendar.current.startOfDay(for: $0.createdAt) <= selected }
    }
    private var dailyDone: Int { dailyHabits.filter { PlannerLogic.progress($0, logs: logs, at: selected) >= $0.target }.count }
    private var dailyProgress: Double {
        guard !dailyHabits.isEmpty else { return 0 }
        return dailyHabits.reduce(0.0) { sum, habit in
            sum + min(1, Double(PlannerLogic.progress(habit, logs: logs, at: selected)) / Double(max(1, habit.target)))
        } / Double(dailyHabits.count)
    }
    private var completedTasks: [PlannerTask] { dayTasks.filter { $0.completedAt != nil } }
    private var markedDays: Set<String> { Set(tasks.compactMap { $0.dueDate.map { PlannerLogic.dayKey($0) } }) }
    private var idea: IdeaPrompt? {
        let active = ideas.filter { !$0.dismissed }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard isToday, !active.isEmpty else { return nil }
        return active[(Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0) % active.count]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    dateHeader
                    if !dailyHabits.isEmpty { progressSummary }
                    habitSection("Daily habits", items: dailyHabits)
                    if !weeklyHabits.isEmpty { habitSection("This week", items: weeklyHabits) }
                    if !overdue.isEmpty { taskSection("Overdue", items: overdue) }
                    taskSection("Schedule", items: scheduled)
                    taskSection("Tasks", items: dayTasks.filter { !$0.hasTime && $0.completedAt == nil })
                    if !completedTasks.isEmpty {
                        DisclosureGroup(isExpanded: $showCompleted) {
                            VStack(spacing: 0) {
                                ForEach(completedTasks) { task in TaskRow(task: task) { editing = task } }
                            }
                        } label: {
                            Text("Completed · \(completedTasks.count)").font(.subheadline).foregroundStyle(.secondary)
                        }.tint(.secondary)
                    }
                    if let idea {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles").foregroundStyle(DayTheme.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Try something new").font(.caption).foregroundStyle(.secondary)
                                Text(idea.text).font(.subheadline)
                            }
                            Spacer(minLength: 0)
                            Button {
                                idea.dismissed = true; idea.shownAt = now; idea.updatedAt = now
                                do { try Mutations.save(context) } catch { self.error = error.localizedDescription }
                            } label: { Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44) }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss idea")
                        }.padding(.vertical, 4)
                    }
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                    .frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DayTheme.canvas(scheme))
            .navigationTitle(isToday ? "Today" : selected.formatted(.dateTime.weekday(.wide)))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isToday { Button("Today") { selected = Calendar.current.startOfDay(for: now) } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New task", systemImage: "checklist") { addingTask = true }
                        Button("New habit", systemImage: "repeat") { addingHabit = true }
                    } label: { Image(systemName: "plus").font(.title3.weight(.medium)) }
                        .accessibilityLabel("Add task or habit")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { quickAddBar }
            .sheet(isPresented: $addingTask) { TaskEditor(initialDate: selected).presentationDragIndicator(.visible) }
            .sheet(isPresented: $addingHabit) { HabitEditor().presentationDragIndicator(.visible) }
            .sheet(item: $editing) { TaskEditor(task: $0).presentationDragIndicator(.visible) }
            .modifier(MutationErrorModifier(error: $error))
            .sensoryFeedback(.success, trigger: feedback)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: dailyDone)
            .onReceive(clock) { updateClock($0) }
            .onChange(of: phase) { _, phase in if phase == .active { updateClock(.now) } }
        }
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selected.formatted(.dateTime.month(.wide).day().year()))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button { moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous week")
                Button { moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next week")
            }.buttonStyle(.plain)
            WeekStrip(selection: $selected, markedDays: markedDays, today: now)
        }
    }

    private var progressSummary: some View {
        DayCard {
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(value: dailyProgress, lineWidth: 6)
                    Text(dailyProgress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(.headline, design: .rounded)).monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }.frame(width: 68, height: 68).padding(4)
                VStack(alignment: .leading, spacing: 5) {
                    Text(dailyDone == dailyHabits.count ? "Daily habits complete" : "Daily progress")
                        .font(.headline)
                    Text("\(dailyDone) of \(dailyHabits.count) habits complete")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if isFuture { Text("Check in when the day arrives").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("Daily habit target progress")
                .accessibilityValue("\(Int(dailyProgress * 100)) percent. \(dailyDone) of \(dailyHabits.count) habits complete.")
        }
    }

    private func habitSection(_ title: String, items: [Habit]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: title, detail: "\(items.count)")
            DayCard {
                if items.isEmpty {
                    QuietEmptyState(title: "No daily habits yet", detail: "Add a habit to start tracking your day.", symbol: "circle.dotted")
                    Button("Add habit", systemImage: "plus", action: { addingHabit = true }).font(.subheadline.weight(.medium))
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { habit in
                            HabitRow(habit: habit, logs: logs, date: selected)
                            if habit.id != items.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                }
            }
        }
    }

    private func taskSection(_ title: String, items: [PlannerTask]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: title, detail: "\(items.count)")
            DayCard {
                if items.isEmpty {
                    QuietEmptyState(title: title == "Schedule" ? "No time blocks" : "All clear",
                        detail: title == "Schedule" ? "Add a task with a time to plan this day." : "New tasks appear here.",
                        symbol: title == "Schedule" ? "calendar" : "checkmark.circle")
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { task in
                            TaskRow(task: task) { editing = task }
                                .draggable(task.id.uuidString)
                                .dropDestination(for: String.self) { ids, _ in reorder(ids, before: task) }
                            if task.id != items.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                }
            }
        }
    }

    private var quickAddBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if quickFocused, !quickText.isEmpty {
                let result = QuickAdd.parse(quickText, now: now)
                if let date = result.date {
                    Label(date.formatted(date: .abbreviated, time: result.hasTime ? .shortened : .omitted), systemImage: "calendar")
                        .font(.caption).foregroundStyle(DayTheme.accent).padding(.horizontal, 12)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(DayTheme.accent)
                TextField("New task", text: $quickText).focused($quickFocused)
                    .submitLabel(.done).onSubmit(quickAdd)
                    .accessibilityHint("You can include a date and time, such as gym tomorrow 6am")
                if !quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: quickAdd) { Image(systemName: "arrow.up.circle.fill").font(.title2).frame(width: 44, height: 44) }
                        .accessibilityLabel("Add task")
                }
            }.padding(.horizontal, 12).frame(minHeight: 48)
                .background(DayTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.padding(.horizontal, 20).padding(.vertical, 10)
            .frame(maxWidth: 700).frame(maxWidth: .infinity).background(.bar)
    }

    private func updateClock(_ date: Date) {
        if Calendar.current.isDate(selected, inSameDayAs: now) { selected = Calendar.current.startOfDay(for: date) }
        now = date
    }
    private func moveWeek(_ offset: Int) {
        selected = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: selected)!
    }
    private func reorder(_ ids: [String], before task: PlannerTask) -> Bool {
        guard !task.hasTime, let id = ids.first,
              let source = tasks.first(where: { $0.id.uuidString == id }),
              !source.hasTime, source.id != task.id else { return false }
        var ordered = tasks.filter { $0.id != source.id }
        guard let index = ordered.firstIndex(where: { $0.id == task.id }) else { return false }
        ordered.insert(source, at: index)
        for (index, item) in ordered.enumerated() { item.sortOrder = index; item.updatedAt = now }
        do { try Mutations.save(context); return true } catch { self.error = error.localizedDescription; return false }
    }
    private func quickAdd() {
        let result = QuickAdd.parse(quickText, now: now)
        guard !result.title.isEmpty else { error = "Enter a task name, for example: gym tomorrow 6am."; return }
        let task = PlannerTask(title: result.title, dueDate: result.date ?? selected, hasTime: result.hasTime)
        task.sortOrder = (tasks.map(\.sortOrder).max() ?? -1) + 1
        context.insert(task)
        do { try Mutations.save(context); quickText = ""; quickFocused = false; feedback += 1 }
        catch { self.error = error.localizedDescription }
    }
}

struct TaskRow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: PlannerTask
    var showTime = true
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Button {
                do {
                    try Mutations.toggle(task, in: context); feedback += 1
                    Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
                } catch { self.error = error.localizedDescription }
            } label: {
                Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(task.completedAt == nil ? Color.secondary : DayTheme.accent)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(task.completedAt == nil ? "Complete \(task.title)" : "Reopen \(task.title)")
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title).font(.body).strikethrough(task.completedAt != nil)
                        .foregroundStyle(task.completedAt == nil ? .primary : .secondary)
                    if (task.hasTime && showTime) || task.priority > 0 || !task.recurrenceRule.isEmpty || !task.subtasks.isEmpty {
                        HStack(spacing: 8) {
                            if showTime, task.hasTime, let date = task.dueDate {
                                Text(date.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                                Text("\(task.durationMinutes) min")
                            }
                            if task.priority > 0 { Image(systemName: "flag.fill").foregroundStyle(DayTheme.accent).accessibilityLabel("Priority \(task.priority)") }
                            if !task.recurrenceRule.isEmpty { Image(systemName: "repeat").accessibilityLabel("Repeating") }
                            if !task.subtasks.isEmpty { Text("\(task.subtasks.filter(\.completed).count)/\(task.subtasks.count)") }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.modifier(MutationErrorModifier(error: $error))
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: task.completedAt)
            .sensoryFeedback(.success, trigger: feedback)
    }
}

struct HabitRow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let habit: Habit
    let logs: [HabitLog]
    let date: Date
    @State private var error: String?
    @State private var feedback = 0
    private var progress: Int { PlannerLogic.progress(habit, logs: logs, at: date) }
    private var isFuture: Bool { Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: .now) }
    private var todayCount: Int {
        logs.filter { $0.habitID == habit.id && $0.dayKey == PlannerLogic.dayKey(date) }.reduce(0) { $0 + $1.count }
    }
    private var streakText: String {
        let count = PlannerLogic.streak(habit, logs: logs, at: date)
        return "\(count) \(habit.frequencyRule == "WEEKLY" ? (count == 1 ? "week" : "weeks") : (count == 1 ? "day" : "days")) in a row"
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: habit.icon).font(.system(size: 17, weight: .medium))
                .foregroundStyle(DayTheme.color(habit.color))
                .frame(width: 36, height: 36)
                .background(DayTheme.color(habit.color).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(habit.title).font(.body)
                Text("\(progress)/\(habit.target) \(habit.frequencyRule == "WEEKLY" ? "this week" : "this day") · \(streakText)")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: increment) {
                ZStack {
                    ProgressRing(value: Double(progress) / Double(max(1, habit.target)), color: DayTheme.color(habit.color), lineWidth: 2.5)
                        .frame(width: 30, height: 30)
                    Image(systemName: progress >= habit.target ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(DayTheme.color(habit.color))
                }.frame(width: 44, height: 44)
            }.buttonStyle(.plain).disabled(isFuture || progress >= habit.target)
                .accessibilityLabel("\(progress >= habit.target ? "Completed" : "Log") \(habit.title)")
                .accessibilityValue("\(progress) of \(habit.target)")
        }.padding(.vertical, 10)
            .contextMenu {
                Button("Undo one check-in", systemImage: "arrow.uturn.backward", action: undo)
                    .disabled(todayCount == 0 || isFuture)
            }
            .accessibilityAction(named: Text("Undo one check-in")) { if todayCount > 0 && !isFuture { undo() } }
            .modifier(MutationErrorModifier(error: $error))
            .sensoryFeedback(.success, trigger: feedback)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: progress)
    }
    private func increment() {
        guard !isFuture else { return }
        do { try Mutations.log(habit, at: date, in: context); feedback += 1; reschedule() }
        catch { self.error = error.localizedDescription }
    }
    private func undo() {
        do { try Mutations.undoLog(habit, at: date, in: context); reschedule() }
        catch { self.error = error.localizedDescription }
    }
    private func reschedule() {
        Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
    }
}
