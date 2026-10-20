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
    var unavailable = false
    var consistency: [Double] = []
    static let placeholder = DayEntry(date: .now, items: [WidgetItem(id: "preview", title: "Morning walk", subtitle: "8:00 AM", habit: false, date: nil)], completedHabits: 1, totalHabits: 3)
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        if context.isPreview { completion(.placeholder) }
        else { Task { @MainActor in completion(Self.read()) } }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.read()
            let refresh = min(Date.now.addingTimeInterval(900), Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!))
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
    @MainActor static func read() -> DayEntry {
        do {
            let container = try Persistence.makeContainer()
            let context = ModelContext(container)
            let tasks = try context.fetch(FetchDescriptor<PlannerTask>())
                .filter { $0.completedAt == nil && TodayRules.onDay(TodayRules.item($0), day: PlannerLogic.dayKey(.now), today: PlannerLogic.dayKey(.now)) }
                .sorted {
                    if $0.hasTime != $1.hasTime { return $0.hasTime }
                    if $0.hasTime { return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                    return $0.sortOrder < $1.sortOrder
                }
            let allHabits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\Habit.createdAt)]))
            let logs = try context.fetch(FetchDescriptor<HabitLog>())
            let habits = allHabits.filter { PlannerLogic.isDue($0, logs: logs, at: .now) }
            let taskItems = tasks.map { task in
                WidgetItem(id: task.id.uuidString, title: task.title,
                    subtitle: task.hasTime ? task.dueDate!.formatted(date: .omitted, time: .shortened) : "",
                    habit: false, date: task.hasTime ? task.dueDate : nil)
            }
            let habitItems = habits.filter { !PlannerLogic.checkedToday($0, logs: logs, at: .now) }.map {
                WidgetItem(id: $0.id.uuidString, title: $0.title,
                    subtitle: PlannerLogic.detail($0, logs: logs, at: .now), habit: true, date: nil)
            }
            return DayEntry(date: .now, items: taskItems + habitItems, completedHabits: habits.count - habitItems.count,
                totalHabits: habits.count, consistency: PlannerLogic.consistencySeries(habits: allHabits, logs: logs, ending: .now, days: 30))
        } catch { return DayEntry(date: .now, items: [], completedHabits: 0, totalHabits: 0, unavailable: true) }
    }
}

struct CompleteItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Item"
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
                        Text(entry.items.first?.title ?? "Nothing left today").font(.headline).lineLimit(1)
                        Text(entry.items.first?.subtitle ?? "").font(.caption)
                    }
                case .systemSmall:
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Orbit", systemImage: "sun.max").font(.caption).foregroundStyle(DayTheme.accent)
                        if let next = entry.items.first(where: { !$0.habit && ($0.date ?? .distantPast) > entry.date }), let date = next.date {
                            Text(date, style: .relative).font(.system(.title2, design: .rounded).bold()).minimumScaleFactor(0.7)
                            Text(next.title).font(.caption).lineLimit(2)
                        } else {
                            Text("\(entry.completedHabits)/\(entry.totalHabits)").font(.system(size: 36, weight: .semibold, design: .rounded))
                            Text("Habits done today").font(.caption)
                        }
                        Spacer(minLength: 0)
                        Text(entry.items.isEmpty ? "Nothing left today" : "\(entry.items.count) left today").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Today").font(.headline)
                            Spacer()
                            Image(systemName: "sun.max").foregroundStyle(DayTheme.accent)
                        }
                        ConsistencyWidgetGrid(values: Array(entry.consistency.suffix(DayTheme.sharedDefaults?.integer(forKey: "consistencyRange") == 30 ? 30 : 7)), compact: true)
                        if entry.items.isEmpty { Text("Nothing left today.").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(entry.items.prefix(family == .systemLarge ? 5 : 2)) { item in
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
                        if entry.items.count > (family == .systemLarge ? 5 : 2) {
                            Text("+\(entry.items.count - (family == .systemLarge ? 5 : 2)) more in Orbit").font(.caption2).foregroundStyle(.secondary)
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
        HabitConsistencyWidget()
        FocusLiveActivity()
    }
}

/// The Today widget's look: today's progress (the original design) or a checklist with ticks.
enum TodayWidgetStyle: String, AppEnum {
    case progress, checklist
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.progress: "Progress", .checklist: "Checklist"]
}
struct TodayWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Today"
    static var description = IntentDescription("Show today’s progress, or a checklist you can tick off.")
    @Parameter(title: "Style", default: .progress) var style: TodayWidgetStyle
}
struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let day: DayEntry
    let style: TodayWidgetStyle
}
struct TodayWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry { TodayWidgetEntry(date: .now, day: .placeholder, style: .progress) }
    func snapshot(for configuration: TodayWidgetConfiguration, in context: Context) async -> TodayWidgetEntry {
        let day = context.isPreview ? DayEntry.placeholder : await MainActor.run { DayProvider.read() }
        return TodayWidgetEntry(date: day.date, day: day, style: configuration.style)
    }
    func timeline(for configuration: TodayWidgetConfiguration, in context: Context) async -> Timeline<TodayWidgetEntry> {
        let entry = await snapshot(for: configuration, in: context)
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: entry.date)!)
        return Timeline(entries: [entry], policy: .after(min(entry.date.addingTimeInterval(900), midnight)))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry
    var body: some View {
        if entry.style == .checklist && !entry.day.unavailable && [WidgetFamily.systemSmall, .systemMedium, .systemLarge].contains(family) {
            ChecklistWidgetView(entry: entry.day)
        } else {
            DayWidgetView(entry: entry.day)
        }
    }
}

/// Today's tasks and habits with a tick for each (CompleteItemIntent), in the chosen accent.
struct ChecklistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry
    private var limit: Int { family == .systemLarge ? 8 : family == .systemMedium ? 3 : 4 }
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                Text(entry.items.isEmpty ? "Done" : "\(entry.items.count) left").font(.caption).foregroundStyle(.secondary)
            }
            if entry.items.isEmpty { Text("Nothing left today.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(entry.items.prefix(limit)) { item in
                HStack(spacing: 8) {
                    Button(intent: CompleteItemIntent(itemID: item.id, isHabit: item.habit)) {
                        Image(systemName: "circle").font(family == .systemSmall ? .body : .title3).foregroundStyle(DayTheme.accent)
                    }.buttonStyle(.plain).accessibilityLabel("\(item.habit ? "Log" : "Complete") \(item.title)")
                    Text(item.title).font(.caption).lineLimit(1)
                    Spacer(minLength: 0)
                    if family != .systemSmall { Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
        }.containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
            .widgetURL(URL(string: "orbit://today"))
    }
}

struct OrbitWidget: Widget {
    let kind = "OrbitAgenda"
    var body: some WidgetConfiguration {
        // Existing widgets keep the Progress style; choose Checklist with Edit Widget.
        AppIntentConfiguration(kind: kind, intent: TodayWidgetConfiguration.self, provider: TodayWidgetProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today")
            .description("Today’s progress, or a checklist you can tick off. Hold the widget and choose Edit Widget to switch.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}
