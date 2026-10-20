import SwiftUI
import SwiftData

struct EveningReview: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [PlannerTask]
    @Query private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @State private var selected: Set<UUID> = []
    @State private var error: String?
    private var completed: Int { tasks.filter { $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false }.count }
    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    LabeledContent("Tasks completed", value: "\(completed)")
                    LabeledContent("Habits checked", value: "\(habits.filter { PlannerLogic.checkedToday($0, logs: logs, at: .now) }.count)")
                }
                Section("Pick up to three for tomorrow") {
                    ForEach(tasks.filter { $0.completedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }) { task in
                        Button {
                            if selected.contains(task.id) { selected.remove(task.id) } else if selected.count < 3 { selected.insert(task.id) }
                        } label: { HStack { Text(task.title).foregroundStyle(.primary); Spacer(); Image(systemName: selected.contains(task.id) ? "checkmark.circle.fill" : "circle") } }
                    }
                }
            }.navigationTitle("Evening Review").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Plan tomorrow") { save() }.disabled(selected.isEmpty) }
                }.modifier(MutationErrorModifier(error: $error))
        }
    }
    private func save() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        for task in tasks where selected.contains(task.id) {
            let old = task.dueDate
            let clock = Calendar.current.dateComponents([.hour, .minute], from: old ?? tomorrow)
            let next = task.hasTime ? Calendar.current.date(bySettingHour: clock.hour!, minute: clock.minute!, second: 0, of: tomorrow)! : tomorrow
            task.dueDate = next; task.updatedAt = .now
            if let old { task.reminders = task.reminders.map { next.addingTimeInterval($0.timeIntervalSince(old)) } }
        }
        do { try Mutations.save(context); Task { try? await refreshReminders(context) }; dismiss() } catch { self.error = error.localizedDescription }
    }
}
