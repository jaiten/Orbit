import SwiftUI
import SwiftData
import UIKit

struct TaskActions: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: PlannerTask
    var edit: (() -> Void)? = nil
    @State private var error: String?
    @State private var calendarDraft: CalendarDraft?
    func body(content: Content) -> some View {
        // A short menu, so the lifted row hardly moves: the everyday actions first, the rest in two groups.
        content.contextMenu {
            if let edit { Button("Edit", systemImage: "pencil", action: edit) }
            if task.completedAt == nil, let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: PlannerLogic.todayDate), task.day != PlannerLogic.dayKey(tomorrow) {
                Button("Do Tomorrow", systemImage: "sunrise") { move { TodayRules.moveToDay(task, day: tomorrow); try Mutations.save(context) } }
            }
            Menu("Start focus timer", systemImage: "timer") {
                ForEach(FocusSession.options(for: task), id: \.self) { minutes in
                    Button(FocusSession.label(minutes)) { startTimer(minutes) }
                }
            }
            Menu("Move", systemImage: "arrow.turn.up.right") {
                if task.day != PlannerLogic.today || task.listID == TodayRules.somedayID {
                    Button("Add to Today", systemImage: "sun.max") { move { TodayRules.moveToDay(task, day: PlannerLogic.todayDate); try Mutations.save(context) } }
                }
                if task.listID != TodayRules.somedayID {
                    Button("Move to Someday", systemImage: "moon.zzz") { move { try TodayRules.moveToSomeday(task, in: context); try Mutations.save(context) } }
                }
            }
            Menu("More", systemImage: "ellipsis.circle") {
                if task.completedAt == nil && task.startedAt == nil {
                    Button("Mark in progress", systemImage: "play.circle") { change { try Mutations.setProgress(task, enabled: true, start: true, in: context) } }
                }
                Button("Send to calendar", systemImage: "calendar.badge.plus") { Task { do { calendarDraft = try await CalendarBridge.shared.draft(for: task) } catch { self.error = error.localizedDescription } } }
                Button("Make It a Habit", systemImage: "repeat") { move { try Conversions.toHabit(task, in: context) } }
                Button("Make It a Note", systemImage: "doc.text") { move { try NoteRules.makeNote(task, in: context) } }
            }
            Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = task.notes.isEmpty ? task.title : task.title + "\n\n" + task.notes }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { move { context.delete(task); try Mutations.save(context) } }
        }
            .sheet(item: $calendarDraft) { CalendarEventEditor(draft: $0).presentationDragIndicator(.visible) }
            .modifier(MutationErrorModifier(error: $error))
    }
    /// A timer means the task is under way.
    private func startTimer(_ minutes: Int) {
        // Not through change(), which stops this task's timer after an edit.
        if task.completedAt == nil && task.startedAt == nil {
            do { try Mutations.setProgress(task, enabled: true, start: true, in: context) } catch { self.error = error.localizedDescription }
        }
        Task { do { try await FocusSession.shared.start(task, minutes: minutes) } catch { self.error = error.localizedDescription } }
    }
    private func change(_ action: () throws -> Void) {
        let id = task.id
        do { try action(); Task { await FocusSession.shared.stopIfMatching(id); do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
    /// A change that takes the row out of its list (another day, Someday, a habit, deleted): the
    /// neighbours close the gap smoothly.
    private func move(_ action: () throws -> Void) {
        CompletionHold.shared.cancel("task-" + task.id.uuidString)
        withAnimation(reduceMotion ? nil : .orbitFold) { change(action) }
    }
}

struct HabitActions: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let habit: Habit
    var edit: (() -> Void)? = nil
    @State private var error: String?
    func body(content: Content) -> some View {
        content.contextMenu {
            if let edit { Button("Edit", systemImage: "pencil", action: edit) }
            Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = habit.title }
            Button("Make It a Task", systemImage: "checklist") { change { try Conversions.toTask(habit, in: context) } }
            Divider()
            Button("Delete habit", systemImage: "trash", role: .destructive) { change { try Conversions.remove(habit, in: context) } }
        }.modifier(MutationErrorModifier(error: $error))
    }

    private func change(_ action: () throws -> Void) {
        CompletionHold.shared.cancel("habit-" + habit.id.uuidString)
        withAnimation(reduceMotion ? nil : .orbitFold) { apply(action) }
    }
    private func apply(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
