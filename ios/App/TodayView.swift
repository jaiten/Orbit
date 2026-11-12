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
    @ObservedObject private var calendars = CalendarBridge.shared

    /// Dated today or earlier and still open, or finished today. Undated and Someday items stay in Lists.
    private var relevant: [PlannerTask] {
        let today = PlannerLogic.dayKey(day)
        return tasks.filter { !$0.note && TodayRules.onDay(TodayRules.item($0), day: today, today: PlannerLogic.today) }
    }
    /// Habits scheduled for the day; a weekly habit drops off once its week is done.
    private var dueHabits: [Habit] { habits.filter { PlannerLogic.plannerDay($0.createdAt) <= PlannerLogic.dayKey(day) && PlannerLogic.isDue($0, logs: logs, at: day) } }
    private var checkedHabits: [Habit] { dueHabits.filter { PlannerLogic.checkedToday($0, logs: logs, at: day) } }
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
            .onChange(of: phase) { _, value in if value == .active { refresh() } }
            .onReceive(TimeChanges.publisher) { _ in refresh() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
            header
            FocusBanner()
            ConflictBanner()
            // The plan, then the day's sections; capture is docked at the bottom.
            if sections.contains("progress") { PlanCard(done: planDone, total: (includeTasks ? relevant.count : 0) + dueHabits.count, accent: accent.fill) }
            ForEach(sections.filter { $0 != "progress" }, id: \.self) { section in
                homeSection(section)
            }
        }
        .padding(.top, CGFloat(DesignTokens.spaceS))
        .padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.bottom, CGFloat(DesignTokens.spaceSection))
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }

    private var planDone: Int { (includeTasks ? relevant.filter { $0.completedAt != nil }.count : 0) + checkedHabits.count }

    /// The daily heading stays above the plan.
    private var header: some View {
        PageHeader(eyebrow: DateText.long(day), title: "Today",
                   subtitle: "") {
            Button { showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 44, height: 44) }.accessibilityLabel("Settings")
        }
    }

    private var completedItems: [TodayItem] {
        (sections.contains("today") ? relevant.filter { $0.completedAt != nil }.map { TodayItem(task: $0) } : []) +
        (sections.contains("routine") ? checkedHabits.map { TodayItem(habit: $0) } : [])
    }

    @ViewBuilder private func homeSection(_ id: String) -> some View {
        switch id {
        case "consistency":
            if !habits.isEmpty || tasks.contains(where: { !$0.note }) { ConsistencyStrip(habits: habits, logs: logs).orbitCard() }
        case "overall": OverallProgressCard(habits: habits, logs: logs, tasks: tasks)
        case "today":
            // Tasks from earlier days simply stay on Today with the rest; move them whenever you like.
            let open = relevant.filter { $0.completedAt == nil }
            let planned = open.sorted { a, b in
                if a.hasTime != b.hasTime { return a.hasTime }
                return a.hasTime ? (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) : a.sortOrder < b.sortOrder
            }
            checklistSection("Your day", note: "", items: planned.map { TodayItem(task: $0) }, empty: relevant.isEmpty ? "Nothing planned. Add a task to get started." : "No more tasks scheduled for today.")
        case "routine":
            let open = dueHabits.filter { !PlannerLogic.checkedToday($0, logs: logs, at: day) }
            if dueHabits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "Habits")
                    Text("Start with something small you want to do regularly.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Add a habit", systemImage: "plus") { addingHabit = true }
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
            } else {
                checklistSection("Habits", note: "", items: open.map { TodayItem(habit: $0) }, empty: "All habits checked for today.")
            }
        case "completed":
            if !completedItems.isEmpty {
                DisclosureGroup(isExpanded: $showingCompleted) {
                    checklist(completedItems).padding(.top, 8)
                } label: {
                    Text("Completed (\(completedItems.count))").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }.accessibilityIdentifier("today-completed")
                    .accessibilityValue(showingCompleted ? "Expanded" : "Collapsed")
            }
        case "calendar": if calendars.connected { calendarSection }
        default:
            if let list = lists.first(where: { "list:" + $0.id.uuidString == id }) {
                checklistSection(list.name, items: tasks.filter { $0.listID == list.id && $0.completedAt == nil && !$0.note }.map { TodayItem(task: $0) }, empty: "No tasks.")
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

    private func checklistSection(_ title: String, note: String = "", items: [TodayItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceS)) {
            SectionLabel(title: title, note: note)
            if items.isEmpty && !empty.isEmpty { Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.vertical, 8) }
            checklist(items)
        }
    }


    /// One grouped card with hairline dividers. Rows stay still during completion; only the check
    /// control animates.
    @ViewBuilder private func checklist(_ items: [TodayItem]) -> some View {
        if !items.isEmpty {
            GroupedRows {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 56) }
                    itemView(item)
                }
            }
        }
    }

    @ViewBuilder private func itemView(_ item: TodayItem) -> some View {
        if let task = item.task {
            TaskRow(task: task) { editing = task }
        }
        if let habit = item.habit {
            HabitRow(habit: habit, logs: logs, date: day, edit: { editingHabit = habit })
        }
    }

    private func refresh() {
        day = PlannerLogic.todayDate
        calendars.reload(); FocusSession.shared.restore()
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
    @Query private var entries: [SyncEntry]
    private var count: Int { entries.filter { $0.conflict != nil }.count }
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
