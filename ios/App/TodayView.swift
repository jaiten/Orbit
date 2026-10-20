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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @Query(sort: \PlannerTask.sortOrder) private var tasks: [PlannerTask]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @AppStorage("homeSections") private var homeSections = "consistency,progress,today,routine,completed,calendar"
    @AppStorage("hiddenHomeSections") private var hiddenSections = ""
    @State private var editing: PlannerTask?
    @State private var editingHabit: Habit?
    @State private var addingTask = false
    @State private var customizing = false
    @State private var reviewing = false
    @State private var completedExpanded = true
    @State private var contentWidth: CGFloat = 0
    @State private var error: String?
    @State private var day = Calendar.current.startOfDay(for: .now)
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 150
    @ObservedObject private var homeDrag = HomeDrag.shared
    @ObservedObject private var calendars = CalendarBridge.shared

    /// Dated today or earlier and still open, or finished today. Undated and Someday items stay in Lists.
    private var relevant: [PlannerTask] {
        let today = PlannerLogic.dayKey(day)
        return tasks.filter { TodayRules.onDay(TodayRules.item($0), day: today, today: today) }
    }
    /// Habits scheduled for the day; a weekly habit drops off once its week is done.
    private var dueHabits: [Habit] { habits.filter { PlannerLogic.isDue($0, logs: logs, at: day) } }
    private var checkedHabits: [Habit] { dueHabits.filter { PlannerLogic.checkedToday($0, logs: logs, at: day) } }
    private var done: Int { relevant.filter { $0.completedAt != nil }.count + checkedHabits.count }
    private var total: Int { relevant.count + dueHabits.count }
    private var sections: [String] {
        let hidden = Set(hiddenSections.split(separator: ",").map(String.init))
        return homeSections.split(separator: ",").map(String.init).filter { !hidden.contains($0) }
    }

    var body: some View {
        NavigationStack {
            page
                .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) { addButton }
                .modifier(TodaySheets(addingTask: $addingTask, reviewing: $reviewing, customizing: $customizing, editing: $editing, editingHabit: $editingHabit))
                .modifier(MutationErrorModifier(error: $error))
        }
    }

    private var page: some View {
        ScrollView { content }
            .scrollDisabled(homeDrag.item != nil)
            .onPreferenceChange(HomeDropFrames.self) { homeDrag.frames = $0 }
            .onPreferenceChange(HomeTileFrames.self) { homeDrag.tiles = $0 }
            .onAppear { homeDrag.accept = { id, routine in _ = move([id], routine: routine) } }
            .onDisappear { homeDrag.reset(); homeDrag.accept = nil }
            .background(DayTheme.canvas(scheme)).tint(accent.fill)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: done)
            .task { refresh(); while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); if !Task.isCancelled { refresh() } } }
            .onChange(of: phase) { _, value in if value == .active { refresh() } }
            .onReceive(TimeChanges.publisher) { _ in refresh() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceXl)) {
            Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
            FocusBanner()
            ConflictBanner()
            ForEach(sections, id: \.self) { section in
                homeSection(section).zIndex(homeDrag.source == section ? 100 : 0)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.onAppear { contentWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in contentWidth = width }
        })
        .padding(.horizontal, CGFloat(DesignTokens.spaceXl)).padding(.bottom, CGFloat(DesignTokens.spaceL))
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        // Hold a tile to move it between Tasks and Habits; one recognizer for the whole page.
        .background(TileHoldInstaller())
        .overlay(alignment: .bottom) {
            if HomeDrag.tracing { Text(homeDrag.trace).font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("drag-trace") }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { customizing = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Edit Today")
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                Button { reviewing = true } label: { Image(systemName: "moon") }.accessibilityLabel("Evening review")
                SyncIndicator()
            }
        }
    }

    private var addButton: some View {
        Button { addingTask = true } label: {
            Image(systemName: "plus").font(.title2.weight(.medium)).foregroundStyle(.white)
                .frame(width: 54, height: 54).background(accent.fill, in: Circle())
                .shadow(color: .black.opacity(0.13), radius: 10, y: 4)
        }.accessibilityLabel("Add").padding(.trailing, 20).padding(.bottom, 10)
    }

    @ViewBuilder private func homeSection(_ id: String) -> some View {
        switch id {
        case "consistency": ConsistencyStrip(habits: habits, logs: logs)
        case "progress":
            HStack(spacing: 14) {
                Text("\(done) of \(total) done").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(max(1, total))).tint(accent.fill).frame(maxWidth: 130)
            }
        case "today":
            checklistSection("Tasks", items: relevant.filter { $0.completedAt == nil }.map { TodayItem(task: $0) }, empty: "Nothing planned for today.")
                .modifier(HomeDropArea(id: "today"))
        case "routine":
            checklistSection("Habits", items: dueHabits.filter { !PlannerLogic.checkedToday($0, logs: logs, at: day) }.map { TodayItem(habit: $0) }, empty: "Hold and drag a task here to make it a habit.")
                .modifier(HomeDropArea(id: "routine"))
        case "completed": completedSection
        case "calendar": if calendars.connected { calendarSection }
        default:
            if let list = lists.first(where: { "list:" + $0.id.uuidString == id }) {
                checklistSection(list.name, items: tasks.filter { $0.listID == list.id && $0.completedAt == nil }.map { TodayItem(task: $0) }, empty: "No tasks.")
            }
        }
    }

    @ViewBuilder private var completedSection: some View {
        let completed = relevant.filter { $0.completedAt != nil }.map { TodayItem(task: $0) } + checkedHabits.map { TodayItem(habit: $0) }
        if !completed.isEmpty {
            DisclosureGroup("Completed · \(completed.count)", isExpanded: $completedExpanded) { checklist(completed).padding(.top, 10) }
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) {
            Text("Calendar").font(.headline)
            if calendars.events.isEmpty { Text("No events today").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(calendars.events, id: \.calendarItemIdentifier) { event in CalendarEventRow(event: event) }
        }
    }

    private func checklistSection(_ title: String, items: [TodayItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceS)) {
            HStack { Text(title).font(.headline); Spacer(); Text("\(items.count)").font(.caption).foregroundStyle(.tertiary) }
            if items.isEmpty { Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8) }
            checklist(items)
        }
    }

    private func checklist(_ items: [TodayItem]) -> some View {
        let compact = !typeSize.isAccessibilitySize && contentWidth >= tileWidth * 2 + CGFloat(DesignTokens.spaceS)
        return VStack(spacing: CGFloat(DesignTokens.spaceS)) {
            ForEach(TodayGroup.groups(items, compact: compact)) { group in
                if group.items.count == 2 {
                    HStack(alignment: .top, spacing: CGFloat(DesignTokens.spaceS)) {
                        ForEach(group.items) { item in itemView(item).frame(maxWidth: .infinity) }
                    }
                } else { itemView(group.items[0]) }
            }
        }
    }

    @ViewBuilder private func itemView(_ item: TodayItem) -> some View {
        if let task = item.task {
            TaskRow(task: task, dragEnabled: true, showMoves: true) { editing = task }.modifier(HomeDragSource(id: "task:" + task.id.uuidString))
        }
        if let habit = item.habit {
            HabitRow(habit: habit, logs: logs, date: day, edit: { editingHabit = habit }).modifier(HomeDragSource(id: "habit:" + habit.id.uuidString))
        }
    }

    private func move(_ values: [String], routine: Bool) -> Bool {
        guard let value = values.first else { return false }
        do {
            if routine, let task = tasks.first(where: { "task:" + $0.id.uuidString == value }) {
                try Conversions.toHabit(task, in: context)
            } else if !routine, let habit = habits.first(where: { "habit:" + $0.id.uuidString == value }) {
                try Conversions.toTask(habit, in: context)
            } else { return false }
            Task { try? await refreshReminders(context) }; return true
        } catch { self.error = error.localizedDescription; return false }
    }

    private func refresh() { day = Calendar.current.startOfDay(for: .now); calendars.reload(); FocusSession.shared.restore() }
}

private struct TodaySheets: ViewModifier {
    @Binding var addingTask: Bool
    @Binding var reviewing: Bool
    @Binding var customizing: Bool
    @Binding var editing: PlannerTask?
    @Binding var editingHabit: Habit?
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $addingTask) { QuickCapture() }
            .sheet(isPresented: $reviewing) { EveningReview() }
            .sheet(isPresented: $customizing) { HomeLayoutEditor() }
            .sheet(item: $editing) { TaskEditor(task: $0) }
            .sheet(item: $editingHabit) { HabitEditor(habit: $0) }
    }
}

/// The running focus timer, if any.
private struct FocusBanner: View {
    @Environment(\.orbitAccent) private var accent
    @ObservedObject private var focus = FocusSession.shared
    var body: some View {
        if let title = focus.title, let end = focus.endsAt {
            HStack {
                Image(systemName: "timer").foregroundStyle(accent.fill)
                Text(title).lineLimit(1)
                Spacer()
                if end > .now { Text(timerInterval: focus.startedAt...end, countsDown: true).monospacedDigit().frame(width: 70) }
                else { Text("Finished").font(.caption) }
                Button("Stop") { Task { await focus.stop() } }.font(.caption)
            }
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
