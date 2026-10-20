import SwiftUI
import SwiftData

struct TaskActions: ViewModifier {
    @Environment(\.modelContext) private var context
    let task: PlannerTask
    @State private var error: String?
    @State private var calendarDraft: CalendarDraft?
    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Start focus timer", systemImage: "timer") { Task { do { try await FocusSession.shared.start(task) } catch { self.error = error.localizedDescription } } }
                Button("Send to calendar", systemImage: "calendar.badge.plus") { Task { do { calendarDraft = try await CalendarBridge.shared.draft(for: task) } catch { self.error = error.localizedDescription } } }
                Button("Move to non-negotiables", systemImage: "repeat") { change { try Conversions.toHabit(task, in: context) } }
                Button("Delete", systemImage: "xmark", role: .destructive) { change { context.delete(task); try Mutations.save(context) } }
            }
            .sheet(item: $calendarDraft) { CalendarEventEditor(draft: $0) }
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
        content.swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { change { try Conversions.remove(habit, in: context) } } label: { Label("Delete", systemImage: "xmark") }
        }.swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { change { try Conversions.toTask(habit, in: context) } } label: { Label("Make to-do", systemImage: "checklist") }.tint(DayTheme.accent)
        }.modifier(MutationErrorModifier(error: $error))
    }
    private func change(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
