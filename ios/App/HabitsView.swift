import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @AppStorage("compactRows") private var compactRows = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var adding = false
    @State private var addingCounter = false
    @State private var editing: Habit?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
                    PageHeader(eyebrow: "", title: "Habits") {
                        Button { addingCounter = true } label: { Label("Counter", systemImage: "plus").font(.subheadline).padding(.horizontal, 14).frame(minHeight: 44).fixedSize(horizontal: true, vertical: false) }
                            .accessibilityLabel("New counter").accessibilityHint("A counter adds one each time you tap it")
                        NavigationLink { HabitHistoryIndex() } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44) }.accessibilityLabel("History")
                    }
                    if habits.isEmpty { ContentUnavailableView("No Habits", systemImage: "repeat", description: Text("Start typing to add a habit.")) }
                    // Every habit's check-ins are read from the logs once, not once for each row.
                    let counts = PlannerLogic.countsByHabit(logs)
                    let regular = habits.filter { !$0.isCounter && !$0.isAvoid }, counters = habits.filter(\.isCounter)
                    let avoiding = habits.filter(\.isAvoid)
                    // Grouped by how often they repeat: Daily (with weekdays and weekends), Weekly, Monthly.
                    ForEach(Self.periods(regular), id: \.name) { group in
                        SectionLabel(title: group.name, note: group.note)
                        VStack(spacing: DayTheme.rowSpacing(compact: compactRows, typeSize: typeSize)) {
                            ForEach(group.habits) { habit in
                                HabitRow(habit: habit, counts: counts[habit.id] ?? [:], date: PlannerLogic.todayDate, edit: { editing = habit })
                                    .transition(.orbitRow)
                            }
                        }.animation(reduceMotion ? nil : .orbitFold, value: group.habits.map(\.id))
                    }
                    // Avoid habits: kept every day unless a slip is marked.
                    if !avoiding.isEmpty {
                        SectionLabel(title: "Avoiding", note: "Kept unless you mark a slip")
                        VStack(spacing: DayTheme.rowSpacing(compact: compactRows, typeSize: typeSize)) {
                            ForEach(avoiding) { habit in
                                AvoidRow(habit: habit, counts: counts[habit.id] ?? [:]) { editing = habit }.transition(.orbitRow)
                            }
                        }.animation(reduceMotion ? nil : .orbitFold, value: avoiding.map(\.id))
                    }
                    // Counters: no target, one more on every tap.
                    if !counters.isEmpty {
                        SectionLabel(title: "Counters", note: "Tap to add one")
                        VStack(spacing: DayTheme.rowSpacing(compact: compactRows, typeSize: typeSize)) {
                            ForEach(counters) { counter in
                                CounterRow(habit: counter, counts: counts[counter.id] ?? [:]) { editing = counter }
                                    .transition(.orbitRow)
                            }
                        }.animation(reduceMotion ? nil : .orbitFold, value: counters.map(\.id))
                    }

                }.padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS))
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.captureDock(scheme) { InlineCapture(habitsOnly: true) }.background(DayTheme.canvas(scheme)).navigationTitle("Habits").navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $adding) { HabitEditor().presentationDragIndicator(.visible) }
                .sheet(isPresented: $addingCounter) { HabitEditor(startsAsCounter: true).presentationDragIndicator(.visible) }.sheet(item: $editing) { HabitEditor(habit: $0).presentationDragIndicator(.visible) }
        }
    }
}

extension HabitsView {
    struct PeriodGroup { let name: String; let note: String; let habits: [Habit] }
    /// Daily (with weekdays and weekends), Weekly and Monthly habits; empty groups are left out.
    /// Same groups as the Habits page on Windows.
    static func periods(_ habits: [Habit]) -> [PeriodGroup] {
        [PeriodGroup(name: "Daily", note: "Each day", habits: habits.filter { HabitRules.period($0.frequencyRule) == nil }),
         PeriodGroup(name: "Weekly", note: "Times this week", habits: habits.filter { HabitRules.period($0.frequencyRule) == "week" }),
         PeriodGroup(name: "Monthly", note: "Times this month", habits: habits.filter { HabitRules.period($0.frequencyRule) == "month" })]
            .filter { !$0.habits.isEmpty }
    }
}

/// Every habit's history on one screen, so there is nothing to open one by one: a card per habit with
/// the last 7 days as segments and the last 12 weeks as a short timeline, in the habit's colour.
struct HabitHistoryIndex: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) {
                Text("Your week and the last 12 weeks. Open a habit for its check-ins.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                ForEach(habits) { habit in
                    VStack(alignment: .leading, spacing: 10) {
                        historyHeading(habit)
                        if habit.isCounter { CounterHistory(habit: habit, counts: PlannerLogic.counts(habit, logs: logs)) }
                        else { HabitHistoryCharts(habit: habit, logs: logs) }
                        NavigationLink { HabitHistoryDetail(habit: habit) } label: {
                            HStack { Text("Full history"); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                                .font(.footnote).foregroundStyle(.secondary)
                        }.accessibilityLabel("Check-ins")
                    }.orbitCard()
                }
            }.padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS))
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(DayTheme.canvas(scheme)).navigationTitle("History").navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func historyHeading(_ habit: Habit) -> some View {
        let count = habit.isCounter ? "Counter" : "\(PlannerLogic.checkedDays(habit, logs: logs, ending: PlannerLogic.todayDate)) of the last 7 days"
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Label { Text(habit.title).font(.body.weight(.semibold)) } icon: {
                    Circle().fill(DayTheme.color(habit.color)).frame(width: DesignTokens.rowDot, height: DesignTokens.rowDot)
                }
                Text(count).font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 10) {
                Circle().fill(DayTheme.color(habit.color)).frame(width: DesignTokens.rowDot, height: DesignTokens.rowDot)
                Text(habit.title).font(.body.weight(.semibold))
                Spacer()
                Text(count).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

}

struct HabitHistoryDetail: View {
    let habit: Habit
    @Environment(\.colorScheme) private var scheme
    @Query private var logs: [HabitLog]
    private var recent: [HabitLog] { logs.filter { $0.habitID == habit.id && $0.count > 0 }.sorted { $0.dayKey > $1.dayKey }.prefix(90).map { $0 } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) {
                    if habit.isCounter {
                        Eyebrow(text: "How often")
                        CounterHistory(habit: habit, counts: PlannerLogic.counts(habit, logs: logs))
                    } else {
                        Eyebrow(text: "\(PlannerLogic.checkedDays(habit, logs: logs, ending: PlannerLogic.todayDate)) of the last 7 days")
                        Text("Tap any of the last seven days to add or remove a check-in.").font(.footnote).foregroundStyle(.secondary)
                        HabitHistoryCharts(habit: habit, logs: logs)
                    }
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
    @Environment(\.modelContext) private var context
    let habit: Habit
    let logs: [HabitLog]
    @State private var error: String?
    @State private var feedback = 0
    var body: some View {
        let color = DayTheme.color(habit.color)
        let week = (-6...0).map { Calendar.current.date(byAdding: .day, value: $0, to: PlannerLogic.todayDate)! }
        let counts = PlannerLogic.counts(habit, logs: logs)
        let target = Double(PlannerLogic.dailyTarget(habit))
        let today = PlannerLogic.today
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
            WeekSegments(done: week.map { PlannerLogic.checkedToday(habit, logs: logs, at: $0) }, days: week, color: color,
                         scheduled: week.map { HabitRules.scheduledOn(rule: habit.frequencyRule, day: PlannerLogic.dayKey($0)) },
                         available: week.map { PlannerLogic.dayKey($0) >= PlannerLogic.plannerDay(habit.createdAt) },
                         toggle: toggle)
            // The last 12 weeks as a timeline across the card: three weeks a row, square cells that
            // fill the width, so it stays short.
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 12 weeks").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                BoxGrid(levels: BoxGrid.days().map { day -> Double? in
                    let key = PlannerLogic.dayKey(day)
                    return key > today ? nil : Double(counts[key] ?? 0) / target
                }, color: color, maximumCell: nil, timeline: 21)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(habit.title), last 12 weeks").accessibilityIdentifier("habit-history-grid")
        }
        .modifier(MutationErrorModifier(error: $error))
        .sensoryFeedback(.success, trigger: feedback)
    }
    private func toggle(_ day: Date) {
        do {
            if PlannerLogic.checkedToday(habit, logs: logs, at: day) { try Mutations.undoLog(habit, at: day, in: context) }
            else { try Mutations.log(habit, at: day, in: context) }
            feedback += 1
            Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } }
        } catch { self.error = error.localizedDescription }
    }
}

struct HabitEditor: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var habit: Habit?
    /// A new item opens as a counter (from Habits' Counter button).
    var startsAsCounter = false
    /// A habit repeats towards a target; a counter just adds one on every tap.
    @State private var counter = false
    /// Something to stay away from: kept every day unless a slip is marked (HabitRules.avoid).
    @State private var avoid = false
    /// A counter's optional daily goal.
    @State private var hasGoal = false
    @State private var goal = 3
    @State private var goalAtMost = false
    @State private var title = ""
    @State private var frequency = "DAILY"
    @State private var target = 1
    @State private var color = "sage"
    @State private var icon = "automatic"
    @State private var reminderEnabled = false
    @State private var reminder = Date.now
    @State private var nudgeEnabled = false
    @State private var nudge = Date.now
    @State private var error: String?
    @State private var confirmDelete = false
    /// The title takes the cursor when the editor opens, ready to type.
    @FocusState private var titleFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title).focused($titleFocused).accessibilityIdentifier("habit-title-input")
                    Picker("Type", selection: Binding(get: { counter ? "counter" : avoid ? "avoid" : "habit" }, set: { kind in
                        withAnimation(.orbit) { counter = kind == "counter"; avoid = kind == "avoid" }
                    })) { Text("Habit").tag("habit"); Text("Counter").tag("counter"); Text("Avoid").tag("avoid") }
                    Picker("Color", selection: $color) { ForEach(DayTheme.colors, id: \.self) { Text($0 == "clay" ? "Coral" : $0.capitalized).tag($0) } }
                    Picker("Icon", selection: $icon) {
                        Label("Automatic", systemImage: ItemIcons.suggested(for: title)).tag("automatic")
                        ForEach(ItemIcons.all) { Label($0.name, systemImage: $0.id).tag($0.id) }
                    }
                }
                if !counter && !avoid { howOften }
                if counter {
                    Section {
                        Toggle("Daily goal", isOn: $hasGoal.animation(.orbit))
                        if hasGoal {
                            Picker("Goal is", selection: $goalAtMost) { Text("At least").tag(false); Text("At most").tag(true) }.pickerStyle(.segmented)
                            Stepper("\(goalAtMost ? "At most" : "At least") \(goal) a day", value: $goal, in: 1...1000).monospacedDigit()
                        }
                    } footer: {
                        Text(hasGoal
                             ? (goalAtMost ? "Like coffees: the count turns red once you pass \(goal)." : "Like glasses of water: the count lights up once you reach \(goal).")
                             : "A counter adds one each time you tap it, so you can see how often it happens. Add a goal if you have a number in mind.")
                    }
                }
                if avoid {
                    Section { EmptyView() } footer: {
                        Text("Something to stay away from, like alcohol or late-night snacks. Every day counts as kept unless you mark a slip, and your streak counts clean days in a row.")
                    }
                }
                if !counter && !avoid { Section {
                    Toggle("Reminder", isOn: $reminderEnabled)
                    if reminderEnabled { DatePicker("At", selection: $reminder, displayedComponents: .hourAndMinute) }
                    Toggle("Second reminder if not done", isOn: $nudgeEnabled)
                    if nudgeEnabled { DatePicker("Nudge at", selection: $nudge, displayedComponents: .hourAndMinute) }
                } header: { Text("Reminders") } footer: { Text("Reminders stop once the habit is checked for the day.") } }
                if let habit, !counter && !avoid { Section { Button("Make It a Task", systemImage: "checklist") {
                    do { try Conversions.toTask(habit, in: context); finish() } catch { self.error = error.localizedDescription }
                } } }
                if habit != nil { Section { Button("Delete habit", role: .destructive) { confirmDelete = true } } }
            }.orbitFormBackground().tint(accent.fill).navigationTitle((habit == nil ? "New " : "Edit ") + (counter ? "Counter" : avoid ? "Habit to Avoid" : "Habit")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onAppear {
                    // A new habit starts in the next colour, so habits mix; any colour can still be chosen.
                    guard let habit else { counter = startsAsCounter; color = (try? QuickAddSaver.nextHabitColor(in: context)) ?? "sage"; return }
                    counter = habit.isCounter; avoid = habit.isAvoid
                    hasGoal = habit.goal != nil; goal = habit.goal ?? 3; goalAtMost = habit.goalKind == "atMost"
                    title = habit.title; frequency = HabitRules.schedule(habit.frequencyRule); target = habit.target; color = habit.color; icon = ItemIcons.all.contains { $0.id == habit.icon } ? habit.icon : "automatic"
                    reminderEnabled = habit.reminderMinutes != nil; nudgeEnabled = habit.nudgeMinutes != nil
                    reminder = time(habit.reminderMinutes ?? 540); nudge = time(habit.nudgeMinutes ?? 1200)
                }.modifier(MutationErrorModifier(error: $error))
                .task { try? await Task.sleep(for: .milliseconds(350)); titleFocused = true }
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
    /// How often: a number of times a day, a week or a month; a daily habit can keep to weekdays or weekends.
    private var howOften: some View {
        let unit = HabitRules.period(frequency) ?? "day"
        let perBinding = Binding<String>(get: { unit }, set: { value in
            // Back to Daily keeps weekdays or weekends if the habit had them.
            withAnimation(.orbit) {
                frequency = value == "week" ? "WEEKLY" : value == "month" ? "MONTHLY"
                    : ["WEEKDAYS", "WEEKENDS"].contains(frequency) ? frequency : "DAILY"
            }
        })
        return Section {
            Picker("Repeats", selection: perBinding) {
                Text("Daily").tag("day"); Text("Weekly").tag("week"); Text("Monthly").tag("month")
            }.pickerStyle(.segmented).accessibilityIdentifier("habit-period")
            Stepper(value: $target, in: 1...1000) {
                Text("\(target) \(target == 1 ? "time" : "times") a \(unit)").monospacedDigit()
            }.accessibilityIdentifier("habit-target")
            if unit == "day" {
                Picker("On", selection: $frequency) {
                    Text("Every day").tag("DAILY"); Text("Weekdays").tag("WEEKDAYS"); Text("Weekends").tag("WEEKENDS")
                }.pickerStyle(.segmented).accessibilityIdentifier("habit-days")
            }
        } header: { Text("How often") } footer: {
            Text(unit == "day"
                 ? "Shows on Today each \(frequency == "WEEKDAYS" ? "weekday" : frequency == "WEEKENDS" ? "weekend day" : "day") until you have done it \(target == 1 ? "once" : "\(target) times")."
                 : "Shows on Today until you have done it \(target == 1 ? "once" : "\(target) times") this \(unit), then rests until the next \(unit) starts.")
        }
    }
    private func time(_ minutes: Int) -> Date { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now)! }
    private func minutes(_ date: Date) -> Int { Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date) }
    private func save() {
        let item = habit ?? Habit(title: title)
        if habit == nil { context.insert(item) }
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Renaming keeps the icon people already know: an automatic icon is fixed to the one it showed.
        var chosenIcon = icon
        if let habit, icon == "automatic", habit.icon == "automatic",
           ItemIcons.suggested(for: habit.title) != ItemIcons.suggested(for: newTitle) {
            chosenIcon = ItemIcons.suggested(for: habit.title)
        }
        item.title = newTitle; item.frequencyRule = counter ? HabitRules.counter : avoid ? HabitRules.avoid : frequency
        item.target = counter || avoid ? 1 : target; item.color = color; item.icon = chosenIcon
        item.goal = counter && hasGoal ? goal : nil; item.goalKind = counter && hasGoal && goalAtMost ? "atMost" : nil
        item.reminderMinutes = reminderEnabled && !counter && !avoid ? minutes(reminder) : nil
        item.nudgeMinutes = nudgeEnabled && !counter && !avoid ? minutes(nudge) : nil; item.updatedAt = .now
        do { try Mutations.save(context); finish() } catch { self.error = error.localizedDescription }
    }
    private func finish() {
        Task { do { try await refreshReminders(context); dismiss() }
            catch { self.error = "Habit saved, but reminders could not update: \(error.localizedDescription)" }
        }
    }
}
