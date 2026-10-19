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
    @State private var editing: PlannerTask?
    @State private var editingHabit: Habit?
    @State private var addingTask = false
    @State private var addingHabit = false
    @State private var completedExpanded = false
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
    var body: some View {
        NavigationStack {
            List {
                Section {
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
                Section("To-dos") {
                    if relevant.allSatisfy({ $0.completedAt != nil }) { Text("A clear checklist. Add something with +.").foregroundStyle(.secondary).font(.subheadline) }
                    ForEach(relevant.filter { $0.completedAt == nil }) { task in
                        TaskRow(task: task) { editing = task }.listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 12))
                    }
                }
                Section("Non-negotiables") {
                    if habits.isEmpty { Text("Choose one small thing to return to.").foregroundStyle(.secondary).font(.subheadline) }
                    ForEach(habits) { habit in
                        HabitRow(habit: habit, logs: logs, date: day, edit: { editingHabit = habit })
                            .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 12))
                    }
                }
                if relevant.contains(where: { $0.completedAt != nil }) {
                    Section {
                        DisclosureGroup("Completed", isExpanded: $completedExpanded) {
                            ForEach(relevant.filter { $0.completedAt != nil }) { task in TaskRow(task: task) { editing = task } }
                        }
                    }
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
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(DayTheme.canvas(scheme))
            .navigationTitle("Today").navigationBarTitleDisplayMode(.large)
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
    private func refresh() { day = Calendar.current.startOfDay(for: .now); calendars.reload(); focus.restore() }
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
                    if task.completedAt != nil { Task { await FocusSession.shared.stopIfMatching(task.id) } }
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
            .modifier(TaskActions(task: task))
            .modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
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
                do { if progress >= habit.target { try Mutations.undoLog(habit, at: date, in: context) } else { try Mutations.log(habit, at: date, in: context) }; feedback += 1
                    Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
                } catch { self.error = error.localizedDescription }
            } label: {
                Image(systemName: progress >= habit.target ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(DayTheme.color(habit.color)).frame(width: 44, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel("\(progress >= habit.target ? "Undo" : "Log") \(habit.title), \(progress) of \(habit.target)")
        }.contentShape(Rectangle()).modifier(HabitActions(habit: habit))
        .contextMenu {
            Button("Move to to-dos", systemImage: "checklist") {
                do { try Conversions.toTask(habit, in: context) } catch { context.rollback(); self.error = error.localizedDescription }
            }
            Button("Delete", systemImage: "xmark", role: .destructive) {
                do { try Conversions.remove(habit, in: context) } catch { context.rollback(); self.error = error.localizedDescription }
            }
            Button("Undo one log today", systemImage: "arrow.uturn.backward") {
                do { try Mutations.undoLog(habit, at: date, in: context)
                    Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
                } catch { self.error = error.localizedDescription }
            }
        }.modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
    }
}
