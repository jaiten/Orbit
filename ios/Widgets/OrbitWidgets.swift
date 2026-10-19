import SwiftUI
import SwiftData
import WidgetKit
import AppIntents

struct WidgetItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let habit: Bool
    let date: Date?
}

struct DayEntry: TimelineEntry {
    let date: Date
    let items: [WidgetItem]
    let completedHabits: Int
    let totalHabits: Int
    let streak: Int
    var unavailable = false
    static let placeholder = DayEntry(date: .now, items: [WidgetItem(id: "preview", title: "A moment to reset", subtitle: "Your next intention", habit: false, date: nil)], completedHabits: 1, totalHabits: 3, streak: 4)
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        if context.isPreview { completion(.placeholder) }
        else { Task { @MainActor in completion(load()) } }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        Task { @MainActor in
            let entry = load()
            let refresh = min(Date.now.addingTimeInterval(900), Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!))
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
    @MainActor private func load() -> DayEntry {
        do {
            let container = try Persistence.makeContainer()
            let context = ModelContext(container)
            let tasks = try context.fetch(FetchDescriptor<PlannerTask>())
                .filter { $0.completedAt == nil && ($0.dueDate.map { Calendar.current.isDateInToday($0) } ?? true) }
                .sorted {
                    if $0.hasTime != $1.hasTime { return $0.hasTime }
                    if $0.hasTime { return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                    return $0.sortOrder < $1.sortOrder
                }
            let habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\Habit.createdAt)]))
            let logs = try context.fetch(FetchDescriptor<HabitLog>())
            let taskItems = tasks.map { task in
                WidgetItem(id: task.id.uuidString, title: task.title,
                    subtitle: task.hasTime ? task.dueDate!.formatted(date: .omitted, time: .shortened) : "At your own pace",
                    habit: false, date: task.hasTime ? task.dueDate : nil)
            }
            let habitItems = habits.filter { PlannerLogic.progress($0, logs: logs, at: .now) < $0.target }.map {
                WidgetItem(id: $0.id.uuidString, title: $0.title,
                    subtitle: "\(PlannerLogic.progress($0, logs: logs, at: .now))/\($0.target)", habit: true, date: nil)
            }
            return DayEntry(date: .now, items: taskItems + habitItems, completedHabits: habits.count - habitItems.count,
                totalHabits: habits.count, streak: habits.map { PlannerLogic.streak($0, logs: logs) }.max() ?? 0)
        } catch { return DayEntry(date: .now, items: [], completedHabits: 0, totalHabits: 0, streak: 0, unavailable: true) }
    }
}

struct CompleteItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete a Orbit item"
    static var openAppWhenRun = false
    @Parameter(title: "Item ID") var itemID: String
    @Parameter(title: "Is habit") var isHabit: Bool
    init() {}
    init(itemID: String, isHabit: Bool) { self.itemID = itemID; self.isHabit = isHabit }
    @MainActor func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        let container = try Persistence.makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if isHabit {
            if let habit = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first {
                try Mutations.log(habit, at: .now, in: context)
            }
        } else if let task = try context.fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.id == id })).first,
                  task.completedAt == nil {
            try Mutations.toggle(task, in: context)
        }
        try await NotificationScheduler.shared.replace(with: NotificationScheduler.reminders(context: context))
        return .result()
    }
}

struct DayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry
    var body: some View {
        Group {
            if entry.unavailable {
                Text("Open Orbit to set up your planner.").font(.caption)
            } else {
                switch family {
                case .accessoryCircular:
                    Gauge(value: Double(entry.completedHabits), in: 0...Double(max(1, entry.totalHabits))) {
                        Image(systemName: "leaf")
                    } currentValueLabel: { Text("\(entry.completedHabits)") }.gaugeStyle(.accessoryCircular)
                case .accessoryRectangular:
                    VStack(alignment: .leading) {
                        Text("ORBIT").font(.caption2.bold())
                        Text(entry.items.first?.title ?? "Room to breathe").font(.headline).lineLimit(1)
                        Text(entry.items.first?.subtitle ?? "Your day, on your terms").font(.caption)
                    }
                case .systemSmall:
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Orbit", systemImage: "sun.max").font(.caption).foregroundStyle(DayTheme.accent)
                        if let next = entry.items.first(where: { !$0.habit && ($0.date ?? .distantPast) > entry.date }), let date = next.date {
                            Text(date, style: .relative).font(.system(.title2, design: .rounded).bold()).minimumScaleFactor(0.7)
                            Text(next.title).font(.caption).lineLimit(2)
                        } else {
                            Text("\(entry.streak)").font(.system(size: 36, weight: .semibold, design: .rounded))
                            Text("Best current habit streak").font(.caption)
                        }
                        Spacer(minLength: 0)
                        Text("\(entry.completedHabits)/\(entry.totalHabits) habits complete").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Today, at a glance").font(.headline)
                            Spacer()
                            Image(systemName: "sun.max").foregroundStyle(DayTheme.accent)
                        }
                        if entry.items.isEmpty { Text("All clear. Enjoy a little breathing room.").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(entry.items.prefix(family == .systemLarge ? 7 : 3)) { item in
                            HStack(spacing: 8) {
                                Button(intent: CompleteItemIntent(itemID: item.id, isHabit: item.habit)) {
                                    Image(systemName: item.habit ? "plus.circle" : "circle").font(.title3).foregroundStyle(DayTheme.accent)
                                }.buttonStyle(.plain).accessibilityLabel("\(item.habit ? "Log" : "Complete") \(item.title)")
                                Text(item.title).font(.caption).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if entry.items.count > (family == .systemLarge ? 7 : 3) {
                            Text("+\(entry.items.count - (family == .systemLarge ? 7 : 3)) more in Orbit").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
            .widgetURL(URL(string: "orbit://today"))
    }
}

@main struct OrbitWidgetBundle: WidgetBundle {
    var body: some Widget {
        OrbitWidget()
        FocusLiveActivity()
    }
}

struct OrbitWidget: Widget {
    let kind = "OrbitAgenda"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DayProvider()) { DayWidgetView(entry: $0) }
            .configurationDisplayName("Your daily rhythm")
            .description("Your next intentions and small daily rituals.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}
