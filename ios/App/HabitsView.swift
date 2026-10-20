import SwiftUI
import SwiftData

struct HabitsView: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @State private var adding = false
    @State private var editing: Habit?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if habits.isEmpty { ContentUnavailableView("No Habits", systemImage: "leaf", description: Text("Tap + to add one.")) }
                    ForEach(habits) { habit in
                        HabitRow(habit: habit, logs: logs, date: .now, edit: { editing = habit })
                    }
                    if !habits.isEmpty {
                        NavigationLink { HabitHistoryIndex() } label: {
                            Label("History", systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        }.background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(DayTheme.canvas(scheme)).navigationTitle("Habits").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("New habit") }
                .sheet(isPresented: $adding) { HabitEditor() }.sheet(item: $editing) { HabitEditor(habit: $0) }
        }
    }
}

struct HabitHistoryIndex: View {
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    var body: some View {
        List(habits) { habit in NavigationLink(habit.title) { HabitHistoryDetail(habit: habit) } }
            .navigationTitle("History").navigationBarTitleDisplayMode(.inline)
    }
}
struct HabitHistoryDetail: View {
    let habit: Habit
    @Query private var logs: [HabitLog]
    var body: some View {
        List {
            Section("Last 12 weeks") { HabitHeatmap(habit: habit, logs: logs) }
            Section("Progress") {
                LabeledContent("Current streak", value: "\(PlannerLogic.streak(habit, logs: logs)) \(habit.frequencyRule == "WEEKLY" ? "weeks" : "days")")
                LabeledContent("Check-ins", value: "\(logs.filter { $0.habitID == habit.id }.reduce(0) { $0 + $1.count })")
            }
            Section("Recent days") {
                ForEach(logs.filter { $0.habitID == habit.id && $0.count > 0 }.sorted { $0.dayKey > $1.dayKey }.prefix(90)) { log in
                    LabeledContent(log.dayKey, value: "\(log.count) check-in\(log.count == 1 ? "" : "s")")
                }
            }
        }.navigationTitle(habit.title).navigationBarTitleDisplayMode(.inline)
    }
}

struct HabitHeatmap: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
    let habit: Habit
    let logs: [HabitLog]
    private var days: [Date] { (-83...0).map { Calendar.current.date(byAdding: .day, value: $0, to: .now)! } }
    var body: some View {
        LazyHGrid(rows: Array(repeating: GridItem(.fixed(12), spacing: 4), count: 7), spacing: 4) {
            ForEach(days, id: \.self) { day in
                let count = logs.filter { $0.habitID == habit.id && $0.dayKey == PlannerLogic.dayKey(day) }.reduce(0) { $0 + $1.count }
                RoundedRectangle(cornerRadius: 3).fill(DayTheme.color(habit.color).opacity(count == 0 ? 0.10 : min(1, 0.35 + Double(count) / Double(PlannerLogic.dailyTarget(habit)) * 0.65)))
                    .frame(width: 12, height: 12)
                    .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)): \(count) completions")
            }
        }.frame(height: 108)
    }
}

struct HabitEditor: View {
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var habit: Habit?
    @State private var title = ""
    @State private var frequency = "DAILY"
    @State private var target = 1
    @State private var color = "sage"
    @State private var icon = "leaf"
    @State private var reminderEnabled = false
    @State private var reminder = Date.now
    @State private var nudgeEnabled = false
    @State private var nudge = Date.now
    @State private var error: String?
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title).accessibilityIdentifier("habit-title-input")
                    Picker("Frequency", selection: $frequency) { Text("Daily").tag("DAILY"); Text("Weekly").tag("WEEKLY") }
                    Stepper("\(target) times per \(frequency == "DAILY" ? "day" : "week")", value: $target, in: 1...1000)
                    Picker("Color", selection: $color) { ForEach(DayTheme.colors, id: \.self) { Text($0.capitalized).tag($0) } }
                    Picker("Icon", selection: $icon) {
                        ForEach(["leaf", "book", "figure.walk", "drop", "heart", "moon", "pencil", "sun.max"], id: \.self) { Label($0, systemImage: $0).tag($0) }
                    }
                }
                Section {
                    Toggle("Reminder", isOn: $reminderEnabled)
                    if reminderEnabled { DatePicker("At", selection: $reminder, displayedComponents: .hourAndMinute) }
                    Toggle("Second reminder if not done", isOn: $nudgeEnabled)
                    if nudgeEnabled { DatePicker("Nudge at", selection: $nudge, displayedComponents: .hourAndMinute) }
                } header: { Text("Reminders") } footer: { Text("Reminders stop once the habit is checked for the day.") }
                if let habit { Section { Button("Make It a Task", systemImage: "checklist") {
                    do { try Conversions.toTask(habit, in: context); finish() } catch { self.error = error.localizedDescription }
                } } }
                if habit != nil { Section { Button("Delete habit", role: .destructive) { confirmDelete = true } } }
            }.tint(DayTheme.accentColor(accentTheme)).navigationTitle(habit == nil ? "New Habit" : "Edit Habit").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onAppear {
                    guard let habit else { return }
                    title = habit.title; frequency = habit.frequencyRule; target = habit.target; color = habit.color; icon = habit.icon
                    reminderEnabled = habit.reminderMinutes != nil; nudgeEnabled = habit.nudgeMinutes != nil
                    reminder = time(habit.reminderMinutes ?? 540); nudge = time(habit.nudgeMinutes ?? 1200)
                }.modifier(MutationErrorModifier(error: $error))
                .confirmationDialog("Delete this habit and its history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete habit", role: .destructive) {
                        guard let habit else { return }
                        do {
                            let id = habit.id
                            for log in try context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id })) { context.delete(log) }
                            context.delete(habit); try Mutations.save(context); finish()
                        } catch { self.error = error.localizedDescription }
                    }
                }
        }
    }
    private func time(_ minutes: Int) -> Date { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now)! }
    private func minutes(_ date: Date) -> Int { Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date) }
    private func save() {
        let item = habit ?? Habit(title: title)
        if habit == nil { context.insert(item) }
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines); item.frequencyRule = frequency
        item.target = target; item.color = color; item.icon = icon
        item.reminderMinutes = reminderEnabled ? minutes(reminder) : nil
        item.nudgeMinutes = nudgeEnabled ? minutes(nudge) : nil; item.updatedAt = .now
        do { try Mutations.save(context); finish() } catch { self.error = error.localizedDescription }
    }
    private func finish() {
        Task { do { try await refreshReminders(context); dismiss() }
            catch { self.error = "Habit saved, but reminders could not update: \(error.localizedDescription)" }
        }
    }
}
