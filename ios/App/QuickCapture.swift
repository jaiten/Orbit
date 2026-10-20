import SwiftUI
import SwiftData

struct QuickCapture: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    var initialDate: Date = .now
    @State private var title = ""
    @State private var repeatRule = ""
    @State private var date = Date.now
    @State private var timed = false
    @State private var listID: UUID?
    @State private var notes = ""
    @State private var error: String?
    @State private var confirmConflict = false
    @State private var conflictTitles: [String] = []
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.title3).focused($focused).accessibilityIdentifier("task-title-input")
                    Text("Try “Read tomorrow 8pm”").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Picker("Repeat", selection: $repeatRule) {
                        Text("Just once").tag("")
                        Text("Daily habit").tag("DAILY")
                        Text("Weekly habit").tag("WEEKLY")
                        Text("Weekdays").tag("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
                        Text("Weekends").tag("FREQ=WEEKLY;BYDAY=SA,SU")
                    }
                    if repeatRule != "DAILY" && repeatRule != "WEEKLY" {
                        DisclosureGroup("When · \(date.formatted(date: .abbreviated, time: .omitted))") {
                            DatePicker("Day", selection: $date, displayedComponents: .date)
                            Toggle("Set a time", isOn: $timed)
                            if timed { DatePicker("At", selection: $date, displayedComponents: .hourAndMinute) }
                        }
                    }
                    DisclosureGroup("More options") {
                        if repeatRule != "DAILY" && repeatRule != "WEEKLY" { TextField("Notes", text: $notes, axis: .vertical) }
                        if repeatRule != "DAILY" && repeatRule != "WEEKLY" {
                            Picker("List", selection: $listID) {
                                Text("Inbox").tag(nil as UUID?)
                                ForEach(lists) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                        Text("You can add reminders, steps and other details using the pencil after saving.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.tint(DayTheme.accentColor(accentTheme)).navigationTitle("New Item").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.confirmationDialog("This time overlaps another plan", isPresented: $confirmConflict, titleVisibility: .visible) { Button("Save anyway") { save(allowConflict: true) }; Button("Change time", role: .cancel) {} } message: { Text(conflictTitles.joined(separator: ", ")) }
                .onAppear { date = initialDate; focused = true }.modifier(MutationErrorModifier(error: $error))
        }
    }
    private func save() { save(allowConflict: false) }
    private func save(allowConflict: Bool) {
        let parsed = QuickAdd.parse(title, plannedDay: date)
        guard !parsed.title.isEmpty else { error = "Add a name as well as a time."; return }
        if repeatRule == "DAILY" || repeatRule == "WEEKLY" {
            let habit = Habit(title: parsed.title, frequencyRule: repeatRule)
            if parsed.hasTime, let date = parsed.date { habit.reminderMinutes = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date) }
            context.insert(habit)
        } else {
            var planned = parsed.date ?? date
            if timed && !parsed.hasTime {
                let clock = Calendar.current.dateComponents([.hour, .minute], from: date)
                planned = Calendar.current.date(bySettingHour: clock.hour!, minute: clock.minute!, second: 0, of: planned)!
            }
            if !repeatRule.isEmpty, let next = PlannerLogic.nextOccurrence(after: Calendar.current.date(byAdding: .day, value: -1, to: planned)!, rule: repeatRule) { planned = next }
            if !allowConflict && (timed || parsed.hasTime) {
                do { conflictTitles = CalendarBridge.shared.conflictTitles(start: planned, duration: 30, excluding: nil, tasks: try context.fetch(FetchDescriptor<PlannerTask>())) }
                catch { self.error = error.localizedDescription; return }
                if !conflictTitles.isEmpty { confirmConflict = true; return }
            }
            let item = PlannerTask(title: parsed.title, dueDate: timed || parsed.hasTime ? planned : Calendar.current.startOfDay(for: planned), hasTime: timed || parsed.hasTime, listID: listID)
            item.notes = notes; item.recurrenceRule = repeatRule
            context.insert(item)
        }
        do { try Mutations.save(context); Task { try? await refreshReminders(context) }; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
