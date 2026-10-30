import SwiftUI
import SwiftData
import UIKit

struct TaskActions: ViewModifier {
    @Environment(\.modelContext) private var context
    let task: PlannerTask
    @State private var error: String?
    @State private var calendarDraft: CalendarDraft?
    func body(content: Content) -> some View {
        content.contextMenu {
                Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = task.notes.isEmpty ? task.title : task.title + "\n\n" + task.notes }
                Button("Start focus timer", systemImage: "timer") { Task { do { try await FocusSession.shared.start(task) } catch { self.error = error.localizedDescription } } }
                Button("Send to calendar", systemImage: "calendar.badge.plus") { Task { do { calendarDraft = try await CalendarBridge.shared.draft(for: task) } catch { self.error = error.localizedDescription } } }
                Button("Add to Today", systemImage: "sun.max") { change { TodayRules.moveToDay(task, day: .now); try Mutations.save(context) } }
                if task.listID != TodayRules.somedayID {
                    Button("Move to Someday", systemImage: "moon.zzz") { change { try TodayRules.moveToSomeday(task, in: context); try Mutations.save(context) } }
                }
                Button("Make It a Habit", systemImage: "repeat") { change { try Conversions.toHabit(task, in: context) } }
                Button("Make It a Note", systemImage: "doc.text") { change { task.isNote = true; task.schedule(nil, hasTime: false); task.reminders = []; task.progressTracking = nil; task.startedAt = nil; task.updatedAt = .now; try Mutations.save(context) } }
                Button("Delete", systemImage: "xmark", role: .destructive) { change { context.delete(task); try Mutations.save(context) } }
        }
            .sheet(item: $calendarDraft) { CalendarEventEditor(draft: $0).presentationDragIndicator(.visible) }
            .modifier(MutationErrorModifier(error: $error))
    }
    private func change(_ action: () throws -> Void) {
        let id = task.id
        do { try action(); Task { await FocusSession.shared.stopIfMatching(id); do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct HabitActions: ViewModifier {
    @Environment(\.modelContext) private var context
    let habit: Habit
    @State private var error: String?
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = habit.title }
            Button("Make It a Task", systemImage: "checklist") { change { try Conversions.toTask(habit, in: context) } }
            Button("Delete habit", systemImage: "trash", role: .destructive) { change { try Conversions.remove(habit, in: context) } }
        }.modifier(MutationErrorModifier(error: $error))
    }

    private func change(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
