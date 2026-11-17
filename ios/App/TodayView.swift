import SwiftUI
import SwiftData
import EventKit
import UIKit
import Combine

/// Midnight, daylight-saving and time-zone changes.
enum TimeChanges {
    static let publisher = NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
        .merge(with: NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
}

/// Today: tasks dated today or earlier, habits due today, and the sections arranged in Edit Today.
struct TodayView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @AppStorage("homeSections") private var homeSections = HomeLayoutEditor.defaultSections
    @AppStorage("hiddenHomeSections") private var hiddenSections = HomeLayoutEditor.defaultHidden
    @AppStorage("progressIncludesTasks") private var includeTasks = true
    @State private var editing: PlannerTask?
    @State private var editingHabit: Habit?
    @State private var addingHabit = false
    @State private var customizing = false
    @State private var showSettings = false
    @AppStorage("todayCompletedExpanded") private var showingCompleted = false
    @State private var error: String?
    @AppStorage("showOverallProgress") private var showOverall = false
    @State private var day = PlannerLogic.todayDate
    /// Each section's tallest height while Today is open (see HeldHeight).
    @State private var heldHeights: [String: CGFloat] = [:]
    @ObservedObject private var calendars = CalendarBridge.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The day's tasks and habits, worked out once for each update of the screen: every section and
    /// row reads from this instead of filtering all the tasks and check-ins again.
    private struct DaySnapshot {
        /// Dated today or earlier and still open, or finished today. Undated and Someday items stay in Lists.
        var relevant: [PlannerTask] = []
        /// Habits scheduled for the day; a weekly habit drops off once its week is done.
        var dueHabits: [Habit] = []
        var checkedHabits: [Habit] = []
        var counts: [UUID: [String: Int]] = [:]
        func checked(_ habit: Habit) -> Bool { checkedHabits.contains { $0.id == habit.id } }
    }
    private var snapshot: DaySnapshot {
        let key = PlannerLogic.dayKey(day), today = PlannerLogic.today
        // Tasks finished on another day are skipped by their time alone, before any day is worked out.
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        var result = DaySnapshot()
        result.relevant = tasks.filter { task in
            if task.note { return false }
            if let finished = task.completedAt {
                let shifted = DayStart.shifted(finished)
                if shifted < day || shifted >= end { return false }
            }
            return TodayRules.onDay(TodayRules.item(task), day: key, today: today)
        }
        result.counts = PlannerLogic.countsByHabit(logs)
        result.dueHabits = habits.filter { PlannerLogic.plannerDay($0.createdAt) <= key && PlannerLogic.isDue($0, counts: result.counts[$0.id] ?? [:], at: day) }
        result.checkedHabits = result.dueHabits.filter { PlannerLogic.checkedToday($0, counts: result.counts[$0.id] ?? [:], at: day) }
        return result
    }
    private var sections: [String] {
        let hidden = Set(hiddenSections.split(separator: ",").map(String.init))
        var values = homeSections.split(separator: ",").map(String.init).filter { !hidden.contains($0) && ($0 != "overall" || showOverall) }; if showOverall && !values.contains("overall") { values.append("overall") }; return values
    }

    var body: some View {
        NavigationStack {
            page
                .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showSettings) { SettingsView().presentationDragIndicator(.visible) }
                .modifier(TodaySheets(addingHabit: $addingHabit, customizing: $customizing, editing: $editing, editingHabit: $editingHabit))
                .modifier(MutationErrorModifier(error: $error))
        }
    }

    private var page: some View {
        ScrollView { content }
            .scrollDismissesKeyboard(.interactively)
            .captureDock(scheme) { InlineCapture() }
            .background(DayTheme.canvas(scheme)).tint(accent.fill)
            .onAppear {
                day = PlannerLogic.todayDate
                let layout = HomeLayoutEditor.upgradedLayout(sections: homeSections, hidden: hiddenSections)
                homeSections = layout.sections
                hiddenSections = layout.hidden
            }
            .task { refresh(); while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); if !Task.isCancelled { refresh() } } }
            .onChange(of: phase) { _, value in if value == .active { refresh() } else { heldHeights = [:] } }
            .onDisappear { heldHeights = [:] }
            .onReceive(TimeChanges.publisher) { _ in refresh() }
    }

    private var content: some View {
        let today = snapshot, shown = sections
        return VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
            header
            FocusBanner()
            ConflictBanner()
            EveningCheckInOffer()
            // The plan, then the day's sections; capture is docked at the bottom.
            if shown.contains("progress") {
                PlanCard(done: (includeTasks ? today.relevant.filter { $0.completedAt != nil }.count : 0) + today.checkedHabits.count,
                         total: (includeTasks ? today.relevant.count : 0) + today.dueHabits.count, accent: accent.fill)
            }
            ForEach(shown.filter { $0 != "progress" && $0 != "completed" }, id: \.self) { section in
                homeSection(section, today, shown).modifier(HeldHeight(id: section, held: $heldHeights))
            }
            // Completed always sits at the bottom of Today, whatever order the other sections are in.
            if shown.contains("completed") { homeSection("completed", today, shown) }
        }
        .padding(.top, CGFloat(DesignTokens.spaceS))
        .padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.bottom, CGFloat(DesignTokens.spaceSection))
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }

    /// The daily heading stays above the plan.
    private var header: some View {
        PageHeader(eyebrow: DateText.long(day), title: "Today",
                   subtitle: "") {
            Button { showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 44, height: 44) }.accessibilityLabel("Settings")
        }
    }

    @ViewBuilder private func homeSection(_ id: String, _ today: DaySnapshot, _ sections: [String]) -> some View {
        switch id {
        case "consistency":
            if !habits.isEmpty || tasks.contains(where: { !$0.note }) { ConsistencyStrip(habits: habits, logs: logs, tasks: tasks).orbitCard() }
        case "overall": OverallProgressCard(habits: habits, logs: logs, tasks: tasks)
        case "today":
            // Tasks from earlier days simply stay on Today with the rest; move them whenever you like.
            let open = today.relevant.filter { $0.completedAt == nil }
            let planned = open.sorted { a, b in
                if a.hasTime != b.hasTime { return a.hasTime }
                return a.hasTime ? (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) : a.sortOrder < b.sortOrder
            }
            checklistSection("Your day", note: "", items: planned.map { TodayItem(task: $0) }, counts: today.counts, empty: today.relevant.isEmpty ? "Nothing planned. Add a task to get started." : "No more tasks scheduled for today.")
        case "routine":
            // Avoid habits have their own group below, ticked in place each night, so never "open" or "completed".
            let open = today.dueHabits.filter { !today.checked($0) && !$0.isAvoid }
            let counters = habits.filter(\.isCounter)
            let avoiding = today.dueHabits.filter(\.isAvoid)
            if today.dueHabits.allSatisfy(\.isAvoid) && !(counters.isEmpty && avoiding.isEmpty) {
                // Only counters so far: no prompt to start a habit.
                EmptyView()
            } else if today.dueHabits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "Habits")
                    Text("Start with something small you want to do regularly.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Add a habit", systemImage: "plus") { addingHabit = true }
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
            } else {
                checklistSection("Habits", note: "", items: Self.habitItems(open), counts: today.counts, empty: "All habits checked for today.")
            }
            if !avoiding.isEmpty {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceS)) {
                    SectionLabel(title: "Avoiding", note: "Tick tonight · hold if you slip")
                    GroupedRows {
                        ForEach(Array(avoiding.enumerated()), id: \.element.id) { index, habit in
                            VStack(spacing: 0) {
                                if index > 0 { Divider().padding(.leading, 56) }
                                HabitRow(habit: habit, counts: today.counts[habit.id] ?? [:], date: PlannerLogic.todayDate, tapChecks: true, edit: { editingHabit = habit })
                            }.transition(.orbitRow)
                        }
                    }.animation(reduceMotion ? nil : .orbitFold, value: avoiding.map(\.id))
                }
            }
            // Counters have no target, so they stay here all day and out of the plan.
            if !counters.isEmpty {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceS)) {
                    SectionLabel(title: "Counters", note: "Tap to add one")
                    GroupedRows {
                        ForEach(Array(counters.enumerated()), id: \.element.id) { index, counter in
                            VStack(spacing: 0) {
                                if index > 0 { Divider().padding(.leading, 56) }
                                CounterRow(habit: counter, counts: today.counts[counter.id] ?? [:]) { editingHabit = counter }
                            }.transition(.orbitRow)
                        }
                    }.animation(reduceMotion ? nil : .orbitFold, value: counters.map(\.id))
                }
            }
        case "completed":
            let completedItems = (sections.contains("today") ? today.relevant.filter { $0.completedAt != nil }.map { TodayItem(task: $0) } : []) +
                (sections.contains("routine") ? today.checkedHabits.filter { !$0.isAvoid }.map { TodayItem(habit: $0) } : [])
            if !completedItems.isEmpty {
                DisclosureGroup(isExpanded: $showingCompleted) {
                    checklist(completedItems, counts: today.counts).padding(.top, 8)
                } label: {
                    Text("Completed (\(completedItems.count))").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .monospacedDigit().contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .orbitFold, value: completedItems.count)
                }.accessibilityIdentifier("today-completed")
                    .accessibilityValue(showingCompleted ? "Expanded" : "Collapsed")
                    .transition(.opacity)
            }
        case "calendar": if calendars.connected { calendarSection }
        default:
            if let list = lists.first(where: { "list:" + $0.id.uuidString == id }) {
                checklistSection(list.name, items: tasks.filter { $0.listID == list.id && $0.completedAt == nil && !$0.note }.map { TodayItem(task: $0) }, counts: today.counts, empty: "No tasks.")
            }
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) {
            Text("Calendar").font(.headline)
            if calendars.events.isEmpty { Text("No events today").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(calendars.events, id: \.calendarItemIdentifier) { event in CalendarEventRow(event: event) }
        }
    }

    private func checklistSection(_ title: String, note: String = "", items: [TodayItem], counts: [UUID: [String: Int]], empty: String) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceS)) {
            SectionLabel(title: title, note: note)
            if items.isEmpty && !empty.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.vertical, 8).transition(.opacity)
            }
            checklist(items, counts: counts)
        }
    }

    /// One grouped card with hairline dividers. A ticked row stays a moment, then fades as its
    /// neighbours close the gap and the card shortens with them; rows that arrive (from sync, Undo or
    /// another screen) open the same way.
    @ViewBuilder private func checklist(_ items: [TodayItem], counts: [UUID: [String: Int]]) -> some View {
        if !items.isEmpty {
            GroupedRows {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 0) {
                        if index > 0 { Divider().padding(.leading, 56) }
                        itemView(item, counts: counts)
                    }.transition(.orbitRow)
                }
            }
            .animation(reduceMotion ? nil : .orbitFold, value: items.map(\.id))
            .transition(.opacity)
        }
    }

    /// Today's habits, daily first, then weekly and monthly ones, each set marked by a small caption rather
    /// than its own heading, so the card stays compact. With only one kind there are no captions.
    static func habitItems(_ habits: [Habit]) -> [TodayItem] {
        let groups: [(String, [Habit])] = [("", habits.filter { HabitRules.period($0.frequencyRule) == nil }),
                                           ("This week", habits.filter { HabitRules.period($0.frequencyRule) == "week" }),
                                           ("This month", habits.filter { HabitRules.period($0.frequencyRule) == "month" })]
            .filter { !$0.1.isEmpty }
        var items: [TodayItem] = []
        for (caption, members) in groups {
            for (index, habit) in members.enumerated() {
                items.append(TodayItem(habit: habit, caption: groups.count > 1 && index == 0 && !caption.isEmpty ? caption : nil))
            }
        }
        return items
    }

    @ViewBuilder private func itemView(_ item: TodayItem, counts: [UUID: [String: Int]]) -> some View {
        if let caption = item.caption {
            Text(caption.uppercased()).font(.caption2.weight(.semibold)).tracking(0.4).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16).padding(.top, 8).padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
        }
        if let task = item.task {
            TaskRow(task: task, tapChecks: true) { editing = task }
        }
        if let habit = item.habit {
            HabitRow(habit: habit, counts: counts[habit.id] ?? [:], date: day, tapChecks: true, edit: { editingHabit = habit })
        }
    }

    private func refresh() {
        if PlannerLogic.dayKey(day) != PlannerLogic.today { heldHeights = [:] }
        day = PlannerLogic.todayDate
        calendars.reload(); FocusSession.shared.restore()
    }

}

/// A Today section keeps its tallest height while Today stays open, so ticking off a task or habit (which
/// leaves its section for Completed) never moves the sections below it. Heights settle when Today is left,
/// Orbit goes to the background, or the day changes. Same as Windows (holdTodayHeights).
private struct HeldHeight: ViewModifier {
    let id: String
    @Binding var held: [String: CGFloat]
    func body(content: Content) -> some View {
        content
            .frame(minHeight: held[id], alignment: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > (held[id] ?? 0) + 0.5 { held[id] = height }
            }
    }
}

private struct TodaySheets: ViewModifier {
    @Binding var addingHabit: Bool
    @Binding var customizing: Bool
    @Binding var editing: PlannerTask?
    @Binding var editingHabit: Habit?
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $addingHabit) { HabitEditor().presentationDragIndicator(.visible) }
            .sheet(isPresented: $customizing) { HomeLayoutEditor().presentationDragIndicator(.visible) }
            .sheet(item: $editing) { TaskEditor(task: $0).presentationDragIndicator(.visible) }
            .sheet(item: $editingHabit) { HabitEditor(habit: $0).presentationDragIndicator(.visible) }
            .onChange(of: addingHabit) { _, showing in if showing { stopDictation() } }
            .onChange(of: customizing) { _, showing in if showing { stopDictation() } }
            .onChange(of: editing?.id) { _, id in if id != nil { stopDictation() } }
            .onChange(of: editingHabit?.id) { _, id in if id != nil { stopDictation() } }
    }
    private func stopDictation() {
        NotificationCenter.default.post(name: Notification.Name("orbitCaptureSubmitted"), object: nil)
    }
}

/// The running focus timer, if any.
private struct FocusBanner: View {
    @Environment(\.orbitAccent) private var accent
    @ObservedObject private var focus = FocusSession.shared
    var body: some View {
        if let title = focus.title, let end = focus.endsAt {
            HStack(spacing: 10) {
                Image(systemName: "timer").foregroundStyle(accent.fill)
                Text(title).lineLimit(1)
                Spacer()
                if end > .now { Text(timerInterval: focus.startedAt...end, countsDown: true).monospacedDigit().frame(width: 70) }
                else { Text("Finished").font(.caption) }
                Button("Stop") { Task { await focus.stop() } }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }.padding(.horizontal, 14).orbitSurface(radius: CGFloat(DesignTokens.radiusRow))
                .accessibilityElement(children: .combine)
        }
    }
}

/// A small notice when sync kept two versions of something; opens the review screen.
private struct ConflictBanner: View {
    @Environment(\.orbitAccent) private var accent
    /// Only entries with a conflict: the outbox holds one entry for every item in the planner.
    @Query(filter: #Predicate<SyncEntry> { $0.conflict != nil }) private var entries: [SyncEntry]
    private var count: Int { entries.count }
    var body: some View {
        if count > 0 {
            NavigationLink { ConflictReviewView() } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(count == 1 ? "1 item has two versions to review" : "\(count) items have two versions to review")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }.font(.subheadline.weight(.medium)).foregroundStyle(accent.text).padding(12)
                    .background(accent.fill.opacity(0.12), in: RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}
