import SwiftUI
import SwiftData

/// How much of the plan the Overview shows: a week, a month, or everything.
enum AgendaScope: String, CaseIterable, Identifiable {
    case day, week, month, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .all: return "All"
        }
    }
    var title: String {
        switch self {
        case .day: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        case .all: return "Everything"
        }
    }
}

/// Week, month and everything: tasks grouped by day (or by when, for everything) and how each habit is going.
struct AgendaView: View {
    let scope: AgendaScope
    let day: Date
    var edit: (PlannerTask) -> Void
    var editHabit: (Habit) -> Void
    @Environment(\.orbitAccent) private var accent
    @Query(sort: \PlannerTask.sortOrder) private var allTasks: [PlannerTask]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var logs: [HabitLog]
    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("agendaCompletedExpanded") private var showCompleted = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var rowSpacing: CGFloat { compactRows && !typeSize.isAccessibilitySize ? 3 : CGFloat(DesignTokens.spaceS) }
    private var tasks: [PlannerTask] { allTasks.filter { !$0.note } }
    /// A titled run of tasks: a day key, or a TaskDateGroup name for everything.
    private struct TaskRun: Identifiable { let id: String; let items: [PlannerTask] }
    private var today: String { PlannerLogic.dayKey(.now) }

    /// The local days in the week or month, in order.
    private var dayKeys: [String] {
        let calendar = Calendar.current
        let component: Calendar.Component = scope == .week ? .weekOfYear : .month
        guard scope != .all, scope != .day, let interval = calendar.dateInterval(of: component, for: day) else { return [] }
        var keys: [String] = []
        var date = interval.start
        while date < interval.end {
            keys.append(PlannerLogic.dayKey(date))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return keys
    }
    private var inRange: [PlannerTask] {
        if scope == .all { return tasks }
        let keys = Set(dayKeys)
        return tasks.filter { $0.day.map(keys.contains) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
            let planned = inRange
            PlanCard(done: planned.filter { $0.completedAt != nil }.count, total: planned.count, accent: accent.fill)
            if scope == .all { everything } else { byDay }
            habitSection
        }
    }

    @ViewBuilder private var byDay: some View {
        let first = dayKeys.first ?? today
        let overdue = tasks.filter { $0.completedAt == nil && ($0.day ?? first) < first && $0.listID != TodayRules.somedayID }
        if !overdue.isEmpty { section("Overdue", note: "\(overdue.count) to review", overdue) }
        let days = dayKeys.map { key in TaskRun(id: key, items: inRange.filter { $0.day == key }) }.filter { !$0.items.isEmpty }
        if days.isEmpty && overdue.isEmpty {
            Text(scope == .week ? "Nothing planned this week." : "Nothing planned this month.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
        ForEach(days) { group in
            let date = QuickAdd.start(of: group.id, time: nil) ?? .now
            section(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), note: group.id == today ? "Today" : "\(group.items.filter { $0.completedAt != nil }.count) of \(group.items.count) done", group.items)
        }
    }

    @ViewBuilder private var everything: some View {
        let groups = TaskDateGroup.allCases.map { group in
            TaskRun(id: group.rawValue, items: tasks.filter { TaskDateGroup.group(day: $0.day, someday: $0.listID == TodayRules.somedayID, completed: $0.completedAt != nil, today: today) == group })
        }.filter { !$0.items.isEmpty }
        if groups.isEmpty { Text("No tasks yet. Add one above.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4) }
        ForEach(groups) { group in
            if group.id == TaskDateGroup.completed.rawValue {
                DisclosureGroup(isExpanded: $showCompleted) {
                    rows(group.items).padding(.top, 8)
                } label: {
                    Text("Completed (\(group.items.count))").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
            } else {
                section(group.id, note: "\(group.items.count)", group.items)
            }
        }
    }

    @ViewBuilder private var habitSection: some View {
        if !habits.isEmpty {
            VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceS)) {
                SectionLabel(title: "Habits", note: scope == .all ? "Since added" : scope.title)
                VStack(spacing: rowSpacing) {
                    ForEach(habits) { habit in
                        let summary = self.summary(habit)
                        Button { editHabit(habit) } label: { HabitSummaryRow(habit: habit, done: summary.done, due: summary.due) }
                            .buttonStyle(OrbitPress())
                    }
                }
            }
        }
    }

    private func section(_ title: String, note: String, _ items: [PlannerTask]) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceS)) {
            SectionLabel(title: title, note: note)
            rows(items)
        }
    }

    private func rows(_ items: [PlannerTask]) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(items.sorted(by: order)) { task in TaskRow(task: task) { edit(task) } }
        }
    }

    private func order(_ a: PlannerTask, _ b: PlannerTask) -> Bool {
        if (a.completedAt == nil) != (b.completedAt == nil) { return a.completedAt == nil }
        if a.hasTime != b.hasTime { return a.hasTime }
        return a.hasTime ? (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) : a.sortOrder < b.sortOrder
    }

    /// Scheduled days in the period, up to today and not before the habit existed, and how many were checked.
    private func summary(_ habit: Habit) -> (done: Int, due: Int) {
        let created = PlannerLogic.dayKey(habit.createdAt)
        var keys: [String]
        if scope == .all {
            keys = []
            var key = created
            while key <= today && keys.count < 3660 { keys.append(key); key = HabitRules.addDays(key, 1) }
        } else {
            keys = dayKeys.filter { $0 <= today && $0 >= created }
        }
        let counts = PlannerLogic.counts(habit, logs: logs)
        let scheduled = keys.filter { HabitRules.scheduledOn(rule: habit.frequencyRule, day: $0) }
        let done = scheduled.filter { HabitRules.checked(rule: habit.frequencyRule, target: habit.target, counts: counts, day: $0) }.count
        return (done, scheduled.count)
    }
}

/// A habit over a period: its icon, title, "4 of 6 days" and a small bar in the habit's colour.
struct HabitSummaryRow: View {
    let habit: Habit
    let done: Int
    let due: Int
    var body: some View {
        let color = DayTheme.color(habit.color)
        HStack(spacing: 12) {
            Image(systemName: ItemIcons.symbol(habit.icon, title: habit.title)).font(.system(size: 18)).foregroundStyle(color).frame(width: 24)
            Text(habit.title).font(.body).foregroundStyle(.primary).lineLimit(2)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(due == 0 ? "Not due yet" : "\(done) of \(due) days").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                Capsule().fill(Color.orbitTrack(DesignTokens.tintProgressTrack)).frame(width: 64, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: due == 0 ? 0 : 64 * CGFloat(done) / CGFloat(due), height: 4)
                    }
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous))
        .orbitSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.title), \(done) of \(due) scheduled days checked")
        .accessibilityHint("Opens the habit")
    }
}

/// Calendar's Overview: every task in the week, the month or everything, and how each habit is going.
struct AgendaSheet: View {
    var day: Date = .now
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.orbitAccent) private var accent
    @AppStorage("overviewScope") private var scope = AgendaScope.week
    @State private var editing: PlannerTask?
    @State private var editingHabit: Habit?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
                    Picker("Show", selection: $scope) {
                        ForEach(AgendaScope.allCases.filter { $0 != .day }) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("overview-scope")
                    AgendaView(scope: scope == .day ? .week : scope, day: day, edit: { editing = $0 }, editHabit: { editingHabit = $0 })
                }
                .padding(.horizontal, CGFloat(DesignTokens.screenPadding)).padding(.vertical, CGFloat(DesignTokens.spaceS))
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(DayTheme.canvas(scheme)).tint(accent.fill)
            .navigationTitle(scope == .day ? AgendaScope.week.title : scope.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { TaskEditor(task: $0) }
            .sheet(item: $editingHabit) { HabitEditor(habit: $0) }
        }
    }
}
