import SwiftUI
import SwiftData
import EventKit

/// Settings: appearance, accent, reminders, calendars, widgets and your data. Account has its own screen.
struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.orbitAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var sync = SyncService.shared
    @State private var message: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: CGFloat(DesignTokens.spaceL)) {
                PageHeader(eyebrow: "Preferences", title: "Settings") { SyncIndicator(textOnly: true) }
                    .padding(.horizontal, 20).padding(.top, 8)
                Form {
                    Section {
                        NavigationLink { AccountView() } label: {
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Account")
                                    Text(sync.email ?? "Sign in").foregroundStyle(.secondary)
                                }.fixedSize(horizontal: false, vertical: true)
                            } else {
                                LabeledContent("Account", value: sync.email ?? "Sign in")
                            }
                        }
                    }
                    Section("Layout") {
                        NavigationLink("Arrange Today") { HomeLayoutEditor() }
                        NavigationLink("Tab order") { NavigationLayoutEditor() }
                    }
                    AppearanceSection()
                    ProgressSection()
                    RemindersSection(message: $message)
                    CalendarsSection(message: $message)

                    DataSection(message: $message)
                    Section("About") {
                        Text("Works offline. Sync runs while Orbit is open and from time to time in the background (Background App Refresh); widget changes sync with them.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.contentMargins(.top, 0, for: .scrollContent).listSectionSpacing(CGFloat(DesignTokens.spaceL))
                .scrollContentBackground(.hidden).background(DayTheme.canvas(scheme))
            }.frame(maxWidth: 760).frame(maxWidth: .infinity).background(DayTheme.canvas(scheme))
                .tint(accent.fill).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .alert("Orbit", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK") { message = nil }
                } message: { Text(message ?? "") }
        }
        .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
    }
}

private struct AppearanceSection: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("sounds") private var sounds = true
    @Query private var tasks: [PlannerTask]
    @Query private var logs: [HabitLog]
    @Query private var habits: [Habit]
    var body: some View {
        let open = Set(Rewards.accents(earned: Rewards.earnedBadges(Rewards.metrics(tasks: tasks, logs: logs, counters: Rewards.counterIDs(habits)))))
        Section("Appearance") {
            // Keep the control in the form while the sheet's presentation appearance changes.
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            }.pickerStyle(.segmented).accessibilityIdentifier("appearance-picker")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 12) {
                ForEach(DayTheme.accents, id: \.self) { name in
                    let locked = !open.contains(name)
                    Button { accentTheme = name } label: {
                        VStack(spacing: 8) {
                            Circle().fill(DayTheme.accentColor(name).opacity(locked ? 0.35 : 1)).frame(width: 34, height: 34)
                                .overlay {
                                    if accentTheme == name { Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white) }
                                    else if locked { Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white) }
                                }
                            Text(name.capitalized).font(.caption2).foregroundStyle(locked ? .secondary : .primary)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).disabled(locked)
                        .accessibilityLabel(name.capitalized + (accentTheme == name ? ", selected" : locked ? ", locked: \(Rewards.unlockedBy(name)?.detail ?? "")" : ""))
                }
            }.padding(.vertical, 6)
            Toggle("Compact habits and tasks", isOn: $compactRows)
            Toggle("Sounds when you finish things", isOn: $sounds)
            NavigationLink { MilestonesView() } label: { Label("Milestones", systemImage: "rosette") }
            ShuffleColoursButton()
            Text("Fits more items by reducing spacing. Larger accessibility text keeps the room it needs.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct RemindersSection: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Binding var message: String?
    @AppStorage("eveningCheckIn") private var evening = -1
    var body: some View {
        Section {
            Button(action: allow) { Label { Text("Allow Notifications") } icon: { Image(systemName: "bell").foregroundStyle(accent.fill) } }
            Picker("Evening check-in", selection: $evening) {
                Text("Off").tag(-1)
                ForEach([19, 20, 21, 22], id: \.self) { hour in
                    Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!.formatted(date: .omitted, time: .shortened)).tag(hour * 60)
                }
            }
            .onChange(of: evening) { _, value in
                Task {
                    if value >= 0 { _ = await NotificationScheduler.shared.requestIfUndecided() }
                    try? await refreshReminders(context)
                }
            }
        } header: { Text("Reminders") } footer: {
            Text("Set reminders on individual tasks and habits. The evening check-in only comes on days something is still left.")
        }
    }
    private func allow() {
        Task {
            do {
                let granted = try await NotificationScheduler.shared.requestPermission()
                if granted { try await refreshReminders(context) }
                message = granted ? "Reminders are on." : "Notifications are off. You can turn them on in iOS Settings → Orbit → Notifications."
            } catch { message = error.localizedDescription }
        }
    }
}

private struct CalendarsSection: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @ObservedObject private var calendars = CalendarBridge.shared
    @AppStorage("calendarFirstWeekday") private var firstWeekday = Calendar.current.firstWeekday
    @AppStorage("calendarShareEnabled") private var shareEnabled = true
    @Binding var message: String?
    private func syncSoon() { Task { await SyncService.shared.run(context) } }
    var body: some View {
        Section {
            Picker("Start week on", selection: $firstWeekday) { Text("Sunday").tag(1); Text("Monday").tag(2) }
            if calendars.connected {
                ForEach(calendars.calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(isOn: Binding(get: { calendars.isShown(calendar) }, set: { calendars.setShown(calendar, $0); syncSoon() })) {
                        HStack(spacing: 10) {
                            Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(calendar.title)
                                if let account = calendar.source?.title { Text(account).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Toggle("Show iCloud calendars on your other devices", isOn: Binding(get: { shareEnabled }, set: { shareEnabled = $0; syncSoon() }))
                Button("Disconnect Calendars", role: .destructive) { calendars.disconnect(); syncSoon() }
            } else {
                Button { Task { do { try await calendars.connect() } catch { message = error.localizedDescription } } } label: {
                    Label { Text("Connect Calendars") } icon: { Image(systemName: "calendar").foregroundStyle(accent.fill) }
                }
            }
        } header: { Text("Calendars") } footer: { Text("Shows events from Apple Calendar, including Google accounts added to your iPhone. Turn a calendar off to hide it in Orbit. With Show on your other devices on, your iCloud calendars also appear in Orbit on Windows (events from two weeks ago to four months ahead), and changes made there are saved when Orbit syncs on this iPhone. Connect Google or Outlook in Orbit on Windows directly.") }
    }
}

private struct ProgressSection: View {
    @Environment(\.modelContext) private var context
    @State private var dayStart = DayStart.minutes
    @State private var error: String?
    @AppStorage("progressIncludesTasks") private var includeTasks = true
    @AppStorage("showOverallProgress") private var showOverall = false
    @AppStorage("overallProgressRange") private var range = 30
    @AppStorage("consistencyRange") private var widgetRange = 7
    var body: some View {
        Section("Today & Progress") {
            Picker("Day starts at", selection: $dayStart) {
                ForEach(DayStart.choices, id: \.self) { Text(DayStart.label($0)).tag($0) }
            }
            .onChange(of: dayStart) { _, value in
                guard value != DayStart.minutes else { return }
                DayStart.choose(value)
                // Saving records the setting for sync and refreshes Today and widgets.
                do { try Mutations.save(context, undoable: false); Task { try? await refreshReminders(context) } } catch { self.error = error.localizedDescription }
            }
            .onAppear { dayStart = DayStart.minutes }
            Text("Until then, check-ins and finished tasks count for the day before. Syncs to your other devices.").font(.footnote).foregroundStyle(.secondary)
            Toggle("Include tasks in daily progress", isOn: $includeTasks)
            Toggle("Show overall progress", isOn: $showOverall)
            Picker("Overall progress", selection: $range) { Text("Past week").tag(7); Text("Past month").tag(30) }
            Picker("Widget history", selection: $widgetRange) { Text("Past week").tag(7); Text("Past month").tag(30) }
            Text("Recent progress shows the last seven days. To correct a habit check-in, open Habits → History.").font(.footnote).foregroundStyle(.secondary)
            NavigationLink { CaptureRulesView() } label: { Label("Quick add rules", systemImage: "at") }
        }
        .modifier(MutationErrorModifier(error: $error))
    }
}

private struct DataSection: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [PlannerTask]
    @Query private var habits: [Habit]
    @Binding var message: String?
    private var hasExamples: Bool {
        tasks.contains { Examples.taskIDs.contains($0.id) } || habits.contains { Examples.habitIDs.contains($0.id) }
    }
    var body: some View {
        Section {
            NavigationLink("Import & Export") { BackupView() }
            if hasExamples {
                Button("Remove Examples") {
                    do { try Examples.remove(in: context); Task { try? await refreshReminders(context) } } catch { message = error.localizedDescription }
                }
            }
        } header: { Text("Data") } footer: {
            if hasExamples { Text("Removes the example tasks, list and habits. Anything you added stays.") }
        }
    }
}

/// Settings → Quick add rules: Someday visibility rules for @tags, abbreviations, and words that always track start & finish.
/// Both sync to your other devices (SomedayRules, CaptureRules).
struct CaptureRulesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bridge = CalendarBridge.shared
    @State private var rules = SomedayRules.rules
    @State private var words = ""
    @State private var shortcuts = ""
    @State private var error: String?
    @Query private var tasks: [PlannerTask]
    /// Open tasks that already had a ruled tag before the rule was saved.
    @State private var alreadyTagged: [PlannerTask] = []
    @State private var askingAboutTagged = false

    var body: some View {
        Form {
            Section {
                Button("Add rule") { rules.append(.init()) }
                Button("Add office and home example") {
                    var office = SomedayRules.Rule()
                    office.tag = "office"; office.title = "Office day"
                    var home = SomedayRules.Rule()
                    home.tag = "home"; home.title = office.title; home.trigger = .noEvent
                    rules.append(contentsOf: [office, home])
                }
            } header: { Text("Someday visibility rules") } footer: {
                Text("Type a configured @tag in a task to keep it in Someday. It appears in Today on matching days. Multiple rules for the same tag mean any can match.")
            }
            ForEach($rules) { $rule in
                Section {
                    TextField("Tag, e.g. office", text: $rule.tag).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Show in Today when", selection: $rule.trigger) {
                        ForEach(SomedayRules.Trigger.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if rule.trigger.usesCalendar {
                        Picker("Calendar", selection: $rule.calendar) {
                            Text("Select a calendar").tag("")
                            ForEach(calendarNames(including: rule.calendar), id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Event title contains", text: $rule.title)
                        if rule.trigger == .noEvent {
                            Text("A missing or hidden calendar cannot trigger this rule.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        DatePicker("Start date", selection: dayBinding($rule.start), displayedComponents: .date)
                        if rule.trigger == .dates {
                            Toggle("Use an end date", isOn: Binding(get: { !rule.end.isEmpty }, set: {
                                rule.end = $0 ? (rule.start.isEmpty ? PlannerLogic.today : rule.start) : ""
                            }))
                            if !rule.end.isEmpty { DatePicker("End date", selection: dayBinding($rule.end), displayedComponents: .date) }
                        } else {
                            Stepper("Every \(rule.interval) \(rule.trigger == .weeks ? "week(s)" : "month(s)")",
                                    value: $rule.interval, in: 1...52)
                        }
                    }
                    Button("Remove rule", role: .destructive) { rules.removeAll { $0.id == rule.id } }
                }
                .onChange(of: rule.trigger) { _, value in
                    if !value.usesCalendar && rule.start.isEmpty { rule.start = PlannerLogic.today }
                }
            }
            Section {
                TextField("mtg = meeting with the team", text: $shortcuts, axis: .vertical)
                    .lineLimit(3...10).font(.body.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("capture-shortcuts")
            } header: { Text("Abbreviations") } footer: {
                Text("One per line, like “gs = grocery shopping #errands”. In quick add the word expands when you type a space after it, here and on Windows. The text can use quick add words like #category, a day or a time.")
            }
            Section {
                TextField("laundry, print, bake", text: $words).autocorrectionDisabled().textInputAutocapitalization(.never)
            } header: { Text("Always track start & finish") } footer: {
                Text("Orbit also learns: after you track start & finish on a task, similar tasks suggest it, and from the second time on they start with it. Turn it off on one to teach it otherwise.")
            }
        }
        .orbitFormBackground()
        .navigationTitle("Quick add rules").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save", action: saveRules) } }
        .onAppear {
            words = CaptureRules.progressWords.joined(separator: ", ")
            shortcuts = CaptureRules.lines(CaptureRules.shortcuts)
        }
        .onDisappear(perform: saveWords)
        .confirmationDialog(alreadyTaggedQuestion, isPresented: $askingAboutTagged, titleVisibility: .visible) {
            Button("Let the Rules Show Them") { moveTaggedToSomeday() }
            Button("Leave Them on Their Days", role: .cancel) { dismiss() }
        } message: { Text("They move to Someday and come back to Today on days a rule matches.") }
        .modifier(MutationErrorModifier(error: $error))
    }

    private var alreadyTaggedQuestion: String {
        alreadyTagged.count == 1 ? "1 open task already has a ruled tag" : "\(alreadyTagged.count) open tasks already have a ruled tag"
    }
    private func moveTaggedToSomeday() {
        do {
            for task in alreadyTagged { try TodayRules.moveToSomeday(task, in: context); task.updatedAt = .now }
            try Mutations.save(context)
            Task { try? await refreshReminders(context) }
        } catch { context.rollback(); self.error = error.localizedDescription; return }
        dismiss()
    }

    private func saveWords() {
        let parsedShortcuts = CaptureRules.parseShortcuts(shortcuts)
        if parsedShortcuts != CaptureRules.shortcuts {
            CaptureRules.save(shortcuts: parsedShortcuts)
            do { try Mutations.save(context, undoable: false) } catch { self.error = error.localizedDescription }
        }
        let parsedWords = Array(Set(words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })).sorted()
        guard parsedWords != CaptureRules.progressWords.sorted() else { return }
        CaptureRules.save(progressWords: parsedWords)
        // Saving records the rules for sync.
        do { try Mutations.save(context, undoable: false) } catch { self.error = error.localizedDescription }
    }

    private func calendarNames(including selection: String) -> [String] {
        var names = Set(bridge.calendars.filter(bridge.isShown).map(\.title))
        if !selection.isEmpty { names.insert(selection) }
        return names.sorted()
    }
    private func dayBinding(_ key: Binding<String>) -> Binding<Date> {
        Binding(get: {
            let parts = key.wrappedValue.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return PlannerLogic.todayDate }
            return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? PlannerLogic.todayDate
        }, set: { key.wrappedValue = PlannerLogic.dayKey($0) })
    }
    private func saveRules() {
        saveWords()
        let values = rules.map { rule in
            var value = rule
            value.tag = value.tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value.tag.hasPrefix("@") { value.tag.removeFirst() }
            return value
        }
        guard values.allSatisfy(\.valid) else { error = "Give each rule a valid tag and select a calendar or dates."; return }
        let old = SomedayRules.rules
        let previousTimestamp = SomedayRules.updatedAt
        do {
            try SomedayRules.save(values)
            try Mutations.save(context, undoable: false)
            let tagged = SomedayRules.untaggedByRule(tasks, rules: values)
            if tagged.isEmpty { dismiss() } else { alreadyTagged = tagged; askingAboutTagged = true }
        } catch {
            if let previous = try? JSONEncoder().encode(old) {
                SomedayRules.defaults.set(previous, forKey: SomedayRules.storageKey)
                SomedayRules.defaults.set(previousTimestamp, forKey: SomedayRules.storageKey + "UpdatedAt")
            }
            self.error = error.localizedDescription
        }
    }
}

/// Settings → Appearance → Shuffle Colours: every habit, task category and note section gets a new colour
/// at random, never the one it had and never the same as the item before it. Same as Windows.
private struct ShuffleColoursButton: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var confirming = false
    @State private var error: String?
    var body: some View {
        Button { confirming = true } label: { Label("Shuffle Colours", systemImage: "shuffle") }
            .confirmationDialog("Give every habit, category and note section a new colour?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Shuffle Colours", action: shuffle)
            }
            .modifier(MutationErrorModifier(error: $error))
    }
    private func shuffle() {
        var previous: String?
        func pick(_ current: String) -> String {
            let choices = DayTheme.colors.filter { $0 != current && $0 != previous }
            let chosen = choices.randomElement() ?? current
            previous = chosen
            return chosen
        }
        for habit in habits { habit.color = pick(habit.color); habit.updatedAt = .now }
        for list in lists where list.id != TodayRules.somedayID { list.color = pick(list.color); list.updatedAt = .now }
        do { try Mutations.save(context) } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

