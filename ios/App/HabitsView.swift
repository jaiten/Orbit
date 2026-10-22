import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @AppStorage("compactRows") private var compactRows = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var planning = false
    @State private var adding = false
    @State private var editing: Habit?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceXxl)) {
                    PageHeader(eyebrow: "Repeats", title: "Habits", subtitle: "Your routines, reminders and progress.") {
                        Button { adding = true } label: { Image(systemName: "plus").frame(width: 36, height: 36) }.accessibilityLabel("New habit")
                    }
                    if !habits.isEmpty {
                        Button("Plan habits in Calendar", systemImage: "calendar.badge.clock") { planning = true }
                            .frame(minHeight: 44)
                    }
                    if habits.isEmpty { ContentUnavailableView("No Habits", systemImage: "repeat", description: Text("Tap + to add one.")) }
                    VStack(spacing: compactRows && !typeSize.isAccessibilitySize ? 3 : CGFloat(DesignTokens.spaceS)) {
                        ForEach(habits) { habit in
                            HabitRow(habit: habit, logs: logs, date: .now, edit: { editing = habit })
                        }
                    }
                    if !habits.isEmpty {
                        NavigationLink { HabitHistoryIndex() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Eyebrow(text: "History")
                                    Text("The last 7 days, for every habit").font(.body).foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            }.orbitCard()
                        }.buttonStyle(OrbitPress()).accessibilityLabel("History")
                    }
                }.padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS))
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(DayTheme.canvas(scheme)).navigationTitle("Habits").navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $adding) { HabitEditor() }.sheet(item: $editing) { HabitEditor(habit: $0) }
                .sheet(isPresented: $planning) { CalendarPlanningView() }
        }
    }
}

/// Every habit's history on one screen, so there is nothing to open one by one: a card per habit with
/// the last 7 days as segments and the last 12 weeks as boxes, in the habit's colour.
struct HabitHistoryIndex: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) {
                Text("The last 7 days and 12 weeks, for every habit.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                ForEach(habits) { habit in
                    VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) {
                        HStack(spacing: 10) {
                            Circle().fill(DayTheme.color(habit.color)).frame(width: DesignTokens.rowDot, height: DesignTokens.rowDot)
                            Text(habit.title).font(.body.weight(.semibold))
                            Spacer()
                            Text("\(PlannerLogic.checkedDays(habit, logs: logs, ending: .now)) of the last 7 days").font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(PlannerLogic.detail(habit, logs: logs, at: .now)).font(.footnote).foregroundStyle(.secondary).padding(.leading, 20).padding(.top, -8)
                        HabitHistoryCharts(habit: habit, logs: logs)
                        NavigationLink { HabitHistoryDetail(habit: habit) } label: {
                            HStack { Text("Check-ins"); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                                .font(.footnote).foregroundStyle(.secondary)
                        }.accessibilityLabel("Check-ins")
                    }.orbitCard()
                }
            }.padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS))
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(DayTheme.canvas(scheme)).navigationTitle("History").navigationBarTitleDisplayMode(.inline)
    }
}

struct HabitHistoryDetail: View {
    let habit: Habit
    @Environment(\.colorScheme) private var scheme
    @Query private var logs: [HabitLog]
    private var recent: [HabitLog] { logs.filter { $0.habitID == habit.id && $0.count > 0 }.sorted { $0.dayKey > $1.dayKey }.prefix(90).map { $0 } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceXxl)) {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) {
                    Eyebrow(text: "\(PlannerLogic.checkedDays(habit, logs: logs, ending: .now)) of the last 7 days")
                    HabitHistoryCharts(habit: habit, logs: logs)
                }.orbitCard()
                VStack(alignment: .leading, spacing: 0) {
                    LabeledContent("Repeats", value: HabitRules.label(habit.frequencyRule)).padding(.vertical, 12)
                    Divider().overlay(Color.orbitLine)
                    LabeledContent("Check-ins", value: "\(logs.filter { $0.habitID == habit.id }.reduce(0) { $0 + $1.count })").padding(.vertical, 12)
                }.padding(.horizontal, 18).orbitSurface(radius: CGFloat(DesignTokens.radiusCard))
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceS)) {
                    SectionLabel(title: "Recent days")
                    if recent.isEmpty { Text("No check-ins yet.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4) }
                    else {
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, log in
                                if index > 0 { Divider().overlay(Color.orbitLine) }
                                LabeledContent(log.dayKey, value: "\(log.count) check-in\(log.count == 1 ? "" : "s")").monospacedDigit().padding(.vertical, 11)
                            }
                        }.padding(.horizontal, 18).orbitSurface(radius: CGFloat(DesignTokens.radiusCard))
                    }
                }
            }.padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS))
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(DayTheme.canvas(scheme)).navigationTitle(habit.title).navigationBarTitleDisplayMode(.inline)
    }
}

/// One habit's last 7 days (segments with weekday letters) and last 12 weeks (boxes).
/// Days it isn't scheduled read as empty, never as missed.
struct HabitHistoryCharts: View {
    let habit: Habit
    let logs: [HabitLog]
    var body: some View {
        let color = DayTheme.color(habit.color)
        let week = (-6...0).map { Calendar.current.date(byAdding: .day, value: $0, to: .now)! }
        let counts = PlannerLogic.counts(habit, logs: logs)
        let target = Double(PlannerLogic.dailyTarget(habit))
        let today = PlannerLogic.dayKey(.now)
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
            WeekSegments(done: week.map { PlannerLogic.checkedToday(habit, logs: logs, at: $0) }, days: week, color: color)
            BoxGrid(levels: BoxGrid.days().map { day -> Double? in
                let key = PlannerLogic.dayKey(day)
                return key > today ? nil : Double(counts[key] ?? 0) / target
            }, color: color)
            .accessibilityLabel("\(habit.title), last 12 weeks")
        }
    }
}

struct HabitEditor: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var habit: Habit?
    @State private var title = ""
    @State private var frequency = "DAILY"
    @State private var target = 1
    @State private var color = "sage"
    @State private var icon = "leaf"
    @State private var calendarMinutes = 15
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
                    Picker("Repeats", selection: $frequency) { ForEach(HabitRules.schedules, id: \.self) { Text(HabitRules.label($0)).tag($0) } }
                    Stepper("\(target) \(target == 1 ? "time" : "times") a \(frequency == "WEEKLY" ? "week" : "day")", value: $target, in: 1...1000)
                    Picker("Color", selection: $color) { ForEach(DayTheme.colors, id: \.self) { Text($0.capitalized).tag($0) } }
                    Picker("Icon", selection: $icon) {
                        ForEach(["leaf", "book", "figure.walk", "drop", "heart", "moon", "pencil", "sun.max"], id: \.self) { Label($0, systemImage: $0).tag($0) }
                    }
                }
                Section {
                    Stepper("\(calendarMinutes) minutes", value: $calendarMinutes, in: 5...240, step: 5)
                } header: { Text("Time for a calendar block") } footer: {
                    Text("Used when you choose Plan habits in Calendar. This setting stays on this iPhone.")
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
            }.tint(accent.fill).navigationTitle(habit == nil ? "New Habit" : "Edit Habit").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onAppear {
                    // A new habit starts in the next colour, so habits mix; any colour can still be chosen.
                    guard let habit else { color = (try? QuickAddSaver.nextHabitColor(in: context)) ?? "sage"; return }
                    calendarMinutes = HabitCalendarPreferences.duration(for: habit.id)
                    title = habit.title; frequency = HabitRules.schedule(habit.frequencyRule); target = habit.target; color = habit.color; icon = habit.icon
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
        do { try Mutations.save(context); HabitCalendarPreferences.setDuration(calendarMinutes, for: item.id); finish() } catch { self.error = error.localizedDescription }
    }
    private func finish() {
        Task { do { try await refreshReminders(context); dismiss() }
            catch { self.error = "Habit saved, but reminders could not update: \(error.localizedDescription)" }
        }
    }
}
