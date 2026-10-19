import SwiftUI
import SwiftData

struct TaskEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    var task: PlannerTask?
    var initialDate: Date?
    @State private var title = ""
    @State private var notes = ""
    @State private var listID: UUID?
    @State private var scheduled = false
    @State private var date = Date.now
    @State private var hasTime = false
    @State private var duration = 30
    @State private var priority = 0
    @State private var recurrence = ""
    @State private var tags = ""
    @State private var subtasks: [Subtask] = []
    @State private var subtaskTitle = ""
    @State private var reminders: [Date] = []
    @State private var error: String?
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task name", text: $title, axis: .vertical).font(.title3)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
                    Picker("List", selection: $listID) {
                        Text("Inbox").tag(nil as UUID?)
                        ForEach(lists) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section("Schedule") {
                    Toggle("Schedule a day", isOn: $scheduled)
                    if scheduled {
                        DatePicker("Day", selection: $date, displayedComponents: .date)
                        Toggle("Time block", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Start", selection: $date, displayedComponents: .hourAndMinute)
                            Stepper("\(duration) minutes", value: $duration, in: 5...1440, step: 5)
                        }
                        Picker("Repeat", selection: $recurrence) {
                            Text("Never").tag(""); Text("Daily").tag("FREQ=DAILY")
                            Text("Weekly").tag("FREQ=WEEKLY"); Text("Monthly").tag("FREQ=MONTHLY")
                        }
                    }
                }
                Section("Details") {
                    Picker("Priority", selection: $priority) {
                        Text("None").tag(0); Text("Low").tag(1); Text("Medium").tag(2); Text("High").tag(3)
                    }
                    TextField("Tags, separated by commas", text: $tags)
                }
                Section("Subtasks") {
                    ForEach($subtasks) { $item in
                        HStack {
                            Toggle("Complete", isOn: $item.completed).labelsHidden()
                            TextField("Step", text: $item.title)
                        }
                    }.onDelete { subtasks.remove(atOffsets: $0) }
                    HStack {
                        TextField("Add a step", text: $subtaskTitle)
                        Button {
                            let value = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty { subtasks.append(Subtask(title: value)); subtaskTitle = "" }
                        } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Add subtask")
                    }
                }
                Section {
                    ForEach(reminders.indices, id: \.self) { index in DatePicker("Reminder \(index + 1)", selection: $reminders[index]) }
                        .onDelete { reminders.remove(atOffsets: $0) }
                    Button("Add reminder", systemImage: "bell.badge") { reminders.append(max(date, Date.now.addingTimeInterval(3600))) }
                } header: { Text("Reminders") } footer: { Text("Enable notifications in Settings. Swipe a reminder to remove it. Past reminders are saved but won’t fire.") }
                if task != nil { Section { Button("Delete task", role: .destructive) { confirmDelete = true } } }
            }
            .navigationTitle(task == nil ? "New task" : "Edit task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear(perform: populate).modifier(MutationErrorModifier(error: $error))
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete task", role: .destructive) { guard let task else { return }; context.delete(task); persistAndClose() }
            } message: { Text("Other recurring occurrences will remain.") }
        }
    }
    private func populate() {
        guard let task else { if let initialDate { scheduled = true; date = initialDate }; return }
        title = task.title; notes = task.notes; listID = task.listID; scheduled = task.dueDate != nil
        date = task.dueDate ?? .now; hasTime = task.hasTime; duration = task.durationMinutes
        priority = task.priority; recurrence = task.recurrenceRule; tags = task.tags.joined(separator: ", ")
        subtasks = task.subtasks; reminders = task.reminders
    }
    private func save() {
        let item = task ?? PlannerTask(title: title)
        if task == nil { context.insert(item) }
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines); item.notes = notes; item.listID = listID
        item.dueDate = scheduled ? (hasTime ? date : Calendar.current.startOfDay(for: date)) : nil
        item.hasTime = scheduled && hasTime; item.durationMinutes = duration
        item.priority = priority; item.recurrenceRule = scheduled ? recurrence : ""
        item.tags = Array(Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        item.subtasks = subtasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        item.reminders = reminders; item.updatedAt = .now
        persistAndClose()
    }
    private func persistAndClose() {
        do { try Mutations.save(context)
            Task {
                do { try await refreshReminders(context); dismiss() }
                catch { self.error = "Your change was saved, but reminders could not update: \(error.localizedDescription)" }
            }
        } catch { self.error = error.localizedDescription }
    }
}
