import SwiftUI
import SwiftData

/// One text field. The chip shows what will be created ("Task · Tomorrow · 6:00 PM") before saving;
/// details can be added afterwards with the pencil.
struct QuickCapture: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    /// The day being viewed (Calendar); nil means today.
    var initialDate: Date? = nil
    /// Adding from Lists: the item lands in this list, undated unless the text names a day.
    var listID: UUID? = nil
    var fromList = false
    @State private var text = ""
    @State private var error: String?
    @State private var confirmConflict = false
    @State private var conflictTitles: [String] = []
    @FocusState private var focused: Bool

    private var defaultDay: DefaultDay {
        if fromList { return .undated }
        if let initialDate, !Calendar.current.isDateInToday(initialDate) { return .day(PlannerLogic.dayKey(initialDate)) }
        return .today
    }
    private var result: QuickAddResult { QuickAdd.parse(text, defaultDay: defaultDay) }
    private var preview: String {
        var value = QuickAdd.describe(result)
        if !value.isEmpty, result.kind == .task, !result.someday, result.list == nil, let name = contextListName { value += " · " + name }
        return value
    }
    private var contextListName: String? {
        listID == TodayRules.somedayID ? "Someday" : lists.first { $0.id == listID }?.name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $text, axis: .vertical)
                        .font(.title3).focused($focused).accessibilityIdentifier("task-title-input")
                        .onSubmit { save() }
                    if !preview.isEmpty {
                        Text(preview).font(.footnote.weight(.medium)).foregroundStyle(accent.fill)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(accent.fill.opacity(0.12), in: Capsule())
                            .accessibilityIdentifier("quick-add-preview")
                    }
                } footer: { Text("Try “gym tomorrow 6pm”, “read every day”, “#work” or “someday”.") }
            }.tint(accent.fill).navigationTitle("New Item").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(result.title.isEmpty) }
                }
                .confirmationDialog("This time overlaps another plan", isPresented: $confirmConflict, titleVisibility: .visible) {
                    Button("Save Anyway") { save(allowConflict: true) }; Button("Change Time", role: .cancel) {}
                } message: { Text(conflictTitles.joined(separator: ", ")) }
                .onAppear { focused = true }.modifier(MutationErrorModifier(error: $error))
        }
    }

    private func save(allowConflict: Bool = false) {
        let result = self.result
        guard !result.title.isEmpty else { return }
        do {
            if result.kind == .habit {
                // Anything that repeats is a habit; a time becomes its reminder.
                let habit = Habit(title: result.title, frequencyRule: result.schedule ?? "DAILY")
                habit.reminderMinutes = result.time
                context.insert(habit)
            } else {
                let start = result.date.flatMap { QuickAdd.start(of: $0, time: result.time) }
                if !allowConflict, result.time != nil, let start {
                    conflictTitles = CalendarBridge.shared.conflictTitles(start: start, duration: 30, excluding: nil, tasks: try context.fetch(FetchDescriptor<PlannerTask>()))
                    if !conflictTitles.isEmpty { confirmConflict = true; return }
                }
                let list = try targetList(result)
                let task = PlannerTask(title: result.title, dueDate: start, hasTime: start != nil && result.time != nil, listID: list)
                if task.listID == TodayRules.somedayID { try TodayRules.moveToSomeday(task, in: context) }
                context.insert(task)
            }
            try Mutations.save(context)
            Task { try? await refreshReminders(context) }
            dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }

    /// Someday wins; then a #list (created when new); then the list being viewed.
    private func targetList(_ result: QuickAddResult) throws -> UUID? {
        if result.someday { try TodayRules.ensureSomeday(context); return TodayRules.somedayID }
        if let name = result.list {
            if let existing = lists.first(where: { $0.id != TodayRules.somedayID && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) { return existing.id }
            let list = TaskList(name: name, sortOrder: lists.count); context.insert(list); return list.id
        }
        // A dated item can't stay in Someday.
        if listID == TodayRules.somedayID && result.date != nil { return nil }
        if listID == TodayRules.somedayID { try TodayRules.ensureSomeday(context) }
        return listID
    }
}
