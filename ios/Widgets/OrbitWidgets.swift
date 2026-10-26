import SwiftUI
import SwiftData
import WidgetKit
import AppIntents

struct WidgetHabit: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static var defaultQuery = WidgetHabitQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct WidgetHabitQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [WidgetHabit] {
        let context = ModelContext(try Persistence.makeContainer())
        let habits = try context.fetch(FetchDescriptor<Habit>())
        return identifiers.compactMap { id in habits.first { $0.id.uuidString == id }.map { WidgetHabit(id: id, title: $0.title) } }
    }
    @MainActor func suggestedEntities() async throws -> [WidgetHabit] {
        let context = ModelContext(try Persistence.makeContainer())
        return try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))
            .map { WidgetHabit(id: $0.id.uuidString, title: $0.title) }
    }
}

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
    /// Today's plan: tasks for today (open or finished today) and habits due today.
    var doneToday = 0
    var totalToday = 0
    /// Overall habit progress per day, oldest first; enough days for the widest Grid widget.
    var consistency: [Double] = []
    /// The first few habits, each with its own days, for the large Grid widget.
    var grids: [HabitGrid] = []
    static let gridDays = 245
    private static let sample = (0..<gridDays).map { Double(($0 * 7 + $0 / 3) % 5) / 4 }
    static let placeholder = DayEntry(date: .now, items: [WidgetItem(id: "preview", title: "Morning walk", subtitle: "8:00 AM", habit: false, date: nil)], completedHabits: 1, totalHabits: 3, doneToday: 2, totalToday: 5,
        consistency: sample, grids: [HabitGrid(id: "1", title: "Read a few pages", color: "lavender", values: sample),
                                     HabitGrid(id: "2", title: "Drink water", color: "sage", values: Array(sample.reversed())),
                                     HabitGrid(id: "3", title: "Move your body", color: "clay", values: sample.map { 1 - $0 })])
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
    @MainActor static func read(gridHabitIDs: [UUID]? = nil) -> DayEntry {
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
            let today = PlannerLogic.dayKey(.now)
            let planned = try context.fetch(FetchDescriptor<PlannerTask>()).filter { TodayRules.onDay(TodayRules.item($0), day: today, today: today) }
            let allHabits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\Habit.createdAt)]))
            let logs = try context.fetch(FetchDescriptor<HabitLog>())
            let gridHabits = gridHabitIDs.flatMap { ids in
                let selected = ids.compactMap { id in allHabits.first { $0.id == id } }
                return selected.isEmpty ? nil : selected
            } ?? allHabits
            let summaryHabits = gridHabitIDs == nil ? allHabits : gridHabits
            let habits = summaryHabits.filter { PlannerLogic.isDue($0, logs: logs, at: .now) }
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
                totalHabits: habits.count, doneToday: planned.filter { $0.completedAt != nil }.count + habits.count - habitItems.count,
                totalToday: planned.count + habits.count, consistency: PlannerLogic.consistencySeries(habits: gridHabits, logs: logs, ending: .now, days: DayEntry.gridDays),
                grids: gridHabits.prefix(3).map { habit in
                    HabitGrid(id: habit.id.uuidString, title: habit.title, color: habit.color,
                              values: PlannerLogic.consistencySeries(habits: [habit], logs: logs, ending: .now, days: DayEntry.gridDays))
                })
        } catch { return DayEntry(date: .now, items: [], completedHabits: 0, totalHabits: 0, unavailable: true) }
    }
}

// CompleteItemIntent lives in Shared/OrbitIntents.swift so the app (Shortcuts, Siri) has it too.

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
                    // A ring, as on the website: the count in the middle and "2 of 5 done" below.
                    VStack(spacing: 8) {
                        Eyebrow(text: "Today").frame(maxWidth: .infinity, alignment: .leading)
                        ZStack {
                            Circle().stroke(Color.orbitTrack(DesignTokens.tintProgressTrack), lineWidth: 8)
                            Circle().trim(from: 0, to: entry.totalToday == 0 ? 0 : CGFloat(entry.doneToday) / CGFloat(entry.totalToday))
                                .stroke(DayTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text("\(entry.doneToday)").font(.title2.weight(.semibold)).monospacedDigit()
                                Text("/\(entry.totalToday)").font(.footnote).foregroundStyle(.secondary)
                            }
                        }.frame(width: 76, height: 76)
                        Text("\(entry.doneToday) of \(entry.totalToday) done").font(.caption).foregroundStyle(.secondary)
                    }
                default:
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: "Your plan")
                        Text("\(entry.doneToday) of \(entry.totalToday) done").font(.title2.weight(.semibold)).tracking(-0.6).monospacedDigit().padding(.top, 2)
                        Capsule().fill(Color.orbitTrack(DesignTokens.tintProgressTrack)).frame(height: 7)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule().fill(DayTheme.accent).frame(width: proxy.size.width * (entry.totalToday == 0 ? 0 : CGFloat(entry.doneToday) / CGFloat(entry.totalToday)))
                                }
                            }.clipShape(Capsule()).padding(.top, 10)
                        if family == .systemLarge {
                            VStack(alignment: .leading, spacing: 10) {
                                if entry.items.isEmpty { Text("Nothing left today.").font(.subheadline).foregroundStyle(.secondary) }
                                ForEach(entry.items.prefix(5)) { item in
                                    HStack(spacing: 10) {
                                        Button(intent: CompleteItemIntent(itemID: item.id, isHabit: item.habit)) {
                                            OrbitTick(done: false, color: DayTheme.accent, size: 22)
                                        }.buttonStyle(.plain).accessibilityLabel("\(item.habit ? "Log" : "Complete") \(item.title)")
                                        Text(item.title).font(.subheadline).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                if entry.items.count > 5 { Text("+\(entry.items.count - 5) more in Orbit").font(.caption2).foregroundStyle(.secondary) }
                            }.padding(.top, 18)
                            Spacer(minLength: 0)
                        } else {
                            Spacer(minLength: 0)
                            if let next = entry.items.first {
                                (Text("Next · ").foregroundStyle(.secondary) + Text(next.title) + Text(next.subtitle.isEmpty ? "" : " · " + next.subtitle).foregroundStyle(.secondary))
                                    .font(.subheadline).lineLimit(1)
                            } else { Text("Nothing left today.").font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
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

/// The Today widget's look: today's progress (the original design), a checklist with ticks,
/// or a grid of small boxes showing habit progress by day.
enum TodayWidgetStyle: String, AppEnum {
    case progress, checklist, grid
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.progress: "Progress", .checklist: "Checklist", .grid: "Grid"]
}
struct TodayWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Today"
    static var description = IntentDescription("Show today’s progress, a checklist you can tick off, or a grid of your habit history.")
    @Parameter(title: "Style", default: .progress) var style: TodayWidgetStyle
    @Parameter(title: "Grid habits") var habits: [WidgetHabit]?
}
struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let day: DayEntry
    let style: TodayWidgetStyle
}
struct TodayWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry { TodayWidgetEntry(date: .now, day: .placeholder, style: .progress) }
    func snapshot(for configuration: TodayWidgetConfiguration, in context: Context) async -> TodayWidgetEntry {
        let selected = configuration.style == .grid ? configuration.habits?.compactMap { UUID(uuidString: $0.id) } : nil
        let day = context.isPreview ? DayEntry.placeholder : await MainActor.run { DayProvider.read(gridHabitIDs: selected) }
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
        if [WidgetFamily.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(family) {
            LockScreenTodayView(entry: entry)
        } else if entry.style == .checklist && !entry.day.unavailable {
            ChecklistWidgetView(entry: entry.day)
        } else if entry.style == .grid && !entry.day.unavailable {
            GridWidgetView(entry: entry.day)
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
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Checklist")
                Spacer()
                Text(entry.items.isEmpty ? "Done" : "\(entry.items.count) left").font(.caption).foregroundStyle(.secondary)
            }
            if entry.items.isEmpty { Text("Nothing left today.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(entry.items.prefix(limit)) { item in
                HStack(spacing: 8) {
                    Button(intent: CompleteItemIntent(itemID: item.id, isHabit: item.habit)) {
                        OrbitTick(done: false, color: DayTheme.accent, size: family == .systemSmall ? 20 : 24)
                    }.buttonStyle(.plain).accessibilityLabel("\(item.habit ? "Log" : "Complete") \(item.title)")
                    Text(item.title).font(family == .systemSmall ? .caption : .subheadline).lineLimit(1)
                    Spacer(minLength: 0)
                    if family != .systemSmall { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
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
            .description("Today’s progress, a checklist, or a grid of your habit history. Hold the widget and choose Edit Widget to switch.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
