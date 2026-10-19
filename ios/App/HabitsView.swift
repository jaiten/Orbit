import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @State private var adding = false
    @State private var editing: Habit?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if habits.isEmpty {
                        DayCard {
                            QuietEmptyState(title: "Your first habit", detail: "Choose something small you want to repeat.", symbol: "repeat")
                            Button("Add habit", systemImage: "plus") { adding = true }
                        }
                    }
                    ForEach(habits) { habit in
                        DayCard {
                            HabitRow(habit: habit, logs: logs, date: .now)
                            HabitHeatmap(habit: habit, logs: logs)
                            HStack {
                                Text("12-week history").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Edit") { editing = habit }.font(.subheadline).frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Edit \(habit.title)")
                            }
                        }
                    }
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(DayTheme.canvas(scheme)).navigationTitle("Habits")
                .toolbar { Button { adding = true } label: { Image(systemName: "plus").font(.title3.weight(.medium)) }.accessibilityLabel("New habit") }
                .sheet(isPresented: $adding) { HabitEditor().presentationDragIndicator(.visible) }
                .sheet(item: $editing) { HabitEditor(habit: $0).presentationDragIndicator(.visible) }
        }
    }
}

struct HabitHeatmap: View {
    let habit: Habit
    let logs: [HabitLog]
    private var days: [Date] {
        let currentWeek = Calendar.current.dateInterval(of: .weekOfYear, for: .now)!.start
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -11, to: currentWeek)!
        return (0..<84).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }
    private var counts: [String: Int] {
        logs.filter { $0.habitID == habit.id }.reduce(into: [:]) { result, log in result[log.dayKey, default: 0] += log.count }
    }
    var body: some View {
        let history = counts
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<12, id: \.self) { week in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { weekday in
                        let day = days[week * 7 + weekday]
                        let count = history[PlannerLogic.dayKey(day), default: 0]
                        let future = day > Date.now
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DayTheme.color(habit.color).opacity(future ? 0.03 : (count == 0 ? 0.10 : min(1, 0.4 + Double(count) / Double(habit.target) * 0.6))))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if Calendar.current.isDateInToday(day) {
                                    RoundedRectangle(cornerRadius: 3).strokeBorder(DayTheme.color(habit.color), lineWidth: 1)
                                }
                            }
                            .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)): \(future ? "Upcoming" : "\(count) check-ins")")
                    }
                }
            }
        }.frame(maxWidth: 420)
    }
}

struct HabitEditor: View {
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
                Section("Habit") {
                    TextField("Habit name", text: $title)
                    Picker("Frequency", selection: $frequency) { Text("Daily").tag("DAILY"); Text("Weekly").tag("WEEKLY") }
                    Stepper("\(target) times per \(frequency == "DAILY" ? "day" : "week")", value: $target, in: 1...1000)
                    Picker("Color", selection: $color) { ForEach(DayTheme.colors, id: \.self) { Text($0.capitalized).tag($0) } }
                    Picker("Icon", selection: $icon) {
                        ForEach(["leaf", "book", "figure.walk", "drop", "heart", "moon", "pencil", "sun.max"], id: \.self) { Label($0, systemImage: $0).tag($0) }
                    }
                }
                Section {
                    Toggle("Daily reminder", isOn: $reminderEnabled)
                    if reminderEnabled { DatePicker("At", selection: $reminder, displayedComponents: .hourAndMinute) }
                    Toggle("Gentle nudge if unfinished", isOn: $nudgeEnabled)
                    if nudgeEnabled { DatePicker("Nudge at", selection: $nudge, displayedComponents: .hourAndMinute) }
                } header: { Text("Reminders") } footer: { Text("Reminders pause once you reach your period’s target. Enable notifications in Settings.") }
                if habit != nil { Section { Button("Delete habit", role: .destructive) { confirmDelete = true } } }
            }.navigationTitle(habit == nil ? "New habit" : "Edit habit").navigationBarTitleDisplayMode(.inline)
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
