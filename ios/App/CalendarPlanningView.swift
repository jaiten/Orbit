import SwiftUI
import SwiftData
import EventKit

/// A day plan is always previewed before writing one-off blocks to the user's calendar.
struct CalendarPlanningView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.orbitAccent) private var accent
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @ObservedObject private var bridge = CalendarBridge.shared
    @State private var day: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var calendarID = ""
    @State private var selected: Set<String> = []
    @State private var minutes: [String: Int] = [:]
    @State private var preview: DailyPlanning.Result?
    @State private var previewWindow: DailyPlanning.Block?
    @State private var error: String?
    @State private var savedToCalendar = false

    init(day: Date = .now) {
        _day = State(initialValue: day)
        _startTime = State(initialValue: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day)!)
        _endTime = State(initialValue: Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: day)!)
    }
    private struct Candidate: Identifiable {
        let id: String
        let title: String
        var habit: Habit?
        var task: PlannerTask?
        var defaultMinutes: Int { habit.map { HabitCalendarPreferences.duration(for: $0.id) } ?? min(1440, max(5, task?.durationMinutes ?? 30)) }
    }
    private var candidates: [Candidate] {
        let key = PlannerLogic.dayKey(day)
        let due = habits.filter { PlannerLogic.isDue($0, logs: logs, at: day) && !PlannerLogic.checkedToday($0, logs: logs, at: day) }
            .map { Candidate(id: "habit:" + $0.id.uuidString, title: $0.title, habit: $0) }
        let open = tasks.filter { $0.completedAt == nil && !$0.hasTime && TodayRules.onDay(TodayRules.item($0), day: key, today: PlannerLogic.dayKey(.now)) }
            .map { Candidate(id: "task:" + $0.id.uuidString, title: $0.title, task: $0) }
        return due + open
    }
    private var writableCalendars: [EKCalendar] { bridge.connected ? bridge.store.calendars(for: .event).filter(\.allowsContentModifications) : [] }
    private var destination: EKCalendar? { writableCalendars.first { $0.calendarIdentifier == calendarID } }
    private func linkKey(_ item: Candidate) -> String {
        if let task = item.task { return "calendarEvent." + task.id.uuidString }
        return "habitCalendarEvent." + item.id + "." + PlannerLogic.dayKey(day)
    }
    private func existingEvent(_ item: Candidate) -> EKEvent? {
        UserDefaults.standard.string(forKey: linkKey(item)).flatMap { bridge.store.event(withIdentifier: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $day, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Finish by", selection: $endTime, displayedComponents: .hourAndMinute)
                } header: { Text("Available hours") } footer: {
                    Text("Orbit suggests time around your calendar events and timed tasks. Review the plan before adding anything.")
                }
                Section("Calendar") {
                    if !bridge.connected {
                        Button("Connect calendars") { Task { do { try await bridge.connect(); chooseCalendar(); resetSelection() } catch { self.error = error.localizedDescription } } }
                    } else if writableCalendars.isEmpty {
                        Text("Add a writable calendar in iPhone Settings to save a plan.").foregroundStyle(.secondary)
                    } else {
                        Picker("Save to", selection: $calendarID) {
                            ForEach(writableCalendars, id: \.calendarIdentifier) { calendar in
                                Text(calendar.title).tag(calendar.calendarIdentifier)
                            }
                        }
                    }
                }
                Section {
                    if candidates.isEmpty { Text("No unscheduled habits or tasks for this day.").foregroundStyle(.secondary) }
                    ForEach(candidates) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            if existingEvent(item) != nil {
                                Label(item.title + " · Already on calendar", systemImage: "calendar.badge.checkmark")
                            } else {
                                Toggle(item.title, isOn: Binding(get: { selected.contains(item.id) }, set: { on in
                                    if on { selected.insert(item.id) } else { selected.remove(item.id) }; preview = nil
                                }))
                                if selected.contains(item.id) {
                                    Stepper("\(minutes[item.id] ?? item.defaultMinutes) minutes", value: Binding(get: { minutes[item.id] ?? item.defaultMinutes }, set: { minutes[item.id] = $0; preview = nil }), in: 5...(item.habit == nil ? 1440 : 240), step: 5)
                                }
                            }
                        }
                    }
                } header: { Text("What to schedule") } footer: {
                    Text("Adds one block per selected habit or task. A block does not mark it complete. Habit durations are saved on this iPhone.")
                }
                Section {
                    Button("Suggest times", action: suggest).disabled(destination == nil || selected.isEmpty || savedToCalendar)
                }
                if let preview {
                    Section("Suggested plan") {
                        ForEach(preview.slots) { slot in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(slot.item.title).font(.body.weight(.medium))
                                Text(slot.start.formatted(date: .omitted, time: .shortened) + " – " + slot.end.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if preview.slots.isEmpty { Text("Nothing fits in these hours. Extend the time window or shorten a duration.") }
                    }
                    if !preview.unscheduled.isEmpty {
                        Section("Doesn’t fit yet") {
                            ForEach(preview.unscheduled) { Text($0.title) }
                            Text("These items will not be added. Adjust their durations or the available hours to include them.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Button("Add \(preview.slots.count) blocks to calendar", action: save)
                            .disabled(preview.slots.isEmpty || destination == nil || savedToCalendar)
                    } footer: { Text("These are one-off events. Editing or completing an item in Orbit does not remove its calendar block.") }
                }
            }
            .navigationTitle("Plan your day").navigationBarTitleDisplayMode(.inline).tint(accent.fill)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(savedToCalendar ? "Done" : "Cancel") { dismiss() } } }
            .onAppear { bridge.reload(); chooseCalendar(); resetSelection() }
            .onChange(of: day) { _, _ in resetSelection() }
            .onChange(of: startTime) { _, _ in preview = nil }
            .onChange(of: endTime) { _, _ in preview = nil }
            .onChange(of: calendarID) { _, _ in preview = nil }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in if !savedToCalendar { preview = nil } }
            .modifier(MutationErrorModifier(error: $error))
        }
    }
    private func chooseCalendar() {
        guard bridge.connected else { calendarID = ""; return }
        let preferred = bridge.store.defaultCalendarForNewEvents?.calendarIdentifier
        calendarID = writableCalendars.first { $0.calendarIdentifier == preferred }?.calendarIdentifier ?? writableCalendars.first?.calendarIdentifier ?? ""
    }
    private func resetSelection() {
        preview = nil
        selected = Set(candidates.filter { !bridge.connected || existingEvent($0) == nil }.map(\.id))
        minutes = [:]
    }
    private func bounds() -> DailyPlanning.Block? {
        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute], from: startTime)
        let end = calendar.dateComponents([.hour, .minute], from: endTime)
        guard let begin = calendar.date(bySettingHour: start.hour!, minute: start.minute!, second: 0, of: day),
              let finish = calendar.date(bySettingHour: end.hour!, minute: end.minute!, second: 0, of: day) else { return nil }
        // Never put a suggested block in the past; round today's current time up to a minute.
        let now = Date(timeIntervalSince1970: ceil(Date.now.timeIntervalSince1970 / 60) * 60)
        return DailyPlanning.Block(start: max(begin, now), end: finish)
    }
    private func busy(in window: DailyPlanning.Block) -> [DailyPlanning.Block] {
        let events = bridge.events(from: window.start, to: window.end).filter {
            $0.availability != .free && (!$0.isAllDay || $0.availability == .busy)
        }.map { DailyPlanning.Block(start: $0.startDate, end: $0.endDate) }
        let timed = tasks.filter { $0.hasTime && $0.completedAt == nil }.compactMap { task -> DailyPlanning.Block? in
            guard let start = task.dueDate else { return nil }
            return DailyPlanning.Block(start: start, end: start.addingTimeInterval(Double(task.durationMinutes) * 60))
        }
        return events + timed
    }
    private func suggest() {
        guard let window = bounds(), window.end > window.start else {
            error = "Choose available hours that finish after the start and leave time in the future."; return
        }
        let items = candidates.filter { selected.contains($0.id) && existingEvent($0) == nil }.map {
            DailyPlanning.Item(id: $0.id, title: $0.title, minutes: minutes[$0.id] ?? $0.defaultMinutes)
        }
        previewWindow = window
        preview = DailyPlanning.suggest(items, from: window.start, to: window.end, busy: busy(in: window))
    }
    private func save() {
        guard let preview, let window = previewWindow, let calendar = destination else { return }
        // Recheck immediately before committing, including changes made in another calendar app.
        let occupied = busy(in: window)
        guard preview.slots.allSatisfy({ slot in
            slot.start >= Date.now && !occupied.contains { PlannerLogic.overlaps(slot.start, slot.end, $0.start, $0.end) }
        }), preview.slots.allSatisfy({ slot in
            candidates.first(where: { $0.id == slot.id }).map { existingEvent($0) == nil } ?? false
        }) else { self.preview = nil; error = "Your day changed. Tap Suggest times to refresh the plan."; return }
        var saved: [(Candidate, EKEvent)] = []
        do {
            for slot in preview.slots {
                guard let item = candidates.first(where: { $0.id == slot.id }) else { continue }
                let event = EKEvent(eventStore: bridge.store)
                event.calendar = calendar; event.title = item.title; event.startDate = slot.start; event.endDate = slot.end
                event.notes = item.task?.notes
                try bridge.store.save(event, span: .thisEvent, commit: false)
                saved.append((item, event))
            }
            try bridge.store.commit()
        } catch { bridge.store.reset(); bridge.reload(); self.preview = nil; self.error = error.localizedDescription; return }
        savedToCalendar = true
        // Record links before saving Orbit's task times, so a retry cannot create duplicates.
        for (item, event) in saved {
            if let id = event.eventIdentifier { UserDefaults.standard.set(id, forKey: linkKey(item)) }
            if let habit = item.habit { HabitCalendarPreferences.setDuration(minutes[item.id] ?? item.defaultMinutes, for: habit.id) }
            if let task = item.task {
                let old = task.dueDate
                task.schedule(event.startDate, hasTime: true); task.durationMinutes = minutes[item.id] ?? item.defaultMinutes; task.updatedAt = .now
                if let old { task.reminders = task.reminders.map { event.startDate.addingTimeInterval($0.timeIntervalSince(old)) } }
            }
        }
        do { try Mutations.save(context); Task { try? await refreshReminders(context) }; bridge.reload(); dismiss() }
        catch { context.rollback(); bridge.reload(); self.error = "Calendar blocks were saved, but Orbit could not save the task times. Your blocks are still in Calendar. \(error.localizedDescription)" }
    }
}
