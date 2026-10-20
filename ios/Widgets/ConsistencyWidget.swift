import WidgetKit
import SwiftUI
import AppIntents

enum ConsistencyRange: String, AppEnum {
    case followApp, week, month
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "History range"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.followApp: "Follow Today", .week: "Past week", .month: "Past month"]
}
struct ConsistencyConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Habit consistency"
    @Parameter(title: "Show", default: .followApp) var range: ConsistencyRange
}
struct ConsistencyEntry: TimelineEntry {
    let date: Date
    let day: DayEntry
    let range: ConsistencyRange
}
struct ConsistencyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ConsistencyEntry { ConsistencyEntry(date: .now, day: .placeholder, range: .week) }
    func snapshot(for configuration: ConsistencyConfiguration, in context: Context) async -> ConsistencyEntry {
        let day = await MainActor.run { DayProvider.read(includeStreak: false) }
        return ConsistencyEntry(date: day.date, day: day, range: configuration.range)
    }
    func timeline(for configuration: ConsistencyConfiguration, in context: Context) async -> Timeline<ConsistencyEntry> {
        let entry = await snapshot(for: configuration, in: context)
        return Timeline(entries: [entry], policy: .after(min(entry.date.addingTimeInterval(900), Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: entry.date)!))))
    }
}
struct ConsistencyWidgetGrid: View {
    let values: [Double]
    var compact = false
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: values.count > 7 ? 10 : 7), spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, fraction in
                RoundedRectangle(cornerRadius: 3).fill(DayTheme.accent.opacity(0.12))
                    .overlay(alignment: .bottom) { GeometryReader { proxy in
                        VStack { Spacer(minLength: 0); DayTheme.accent.frame(height: proxy.size.height * min(1, max(0, fraction))) }
                    }.clipShape(RoundedRectangle(cornerRadius: 3)) }
                    .frame(height: compact ? 8 : (values.count > 7 ? 18 : 30))
                    .accessibilityLabel("\(values.count - 1 - index) days ago, \(Int(fraction * 100)) percent")
            }
        }
    }
}
struct HabitConsistencyWidget: Widget {
    let kind = "OrbitConsistency"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConsistencyConfiguration.self, provider: ConsistencyProvider()) { entry in
            let count = entry.range == .month || (entry.range == .followApp && DayTheme.sharedDefaults?.integer(forKey: "consistencyRange") == 30) ? 30 : 7
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Orbit").font(.headline); Spacer(); Image(systemName: "leaf").foregroundStyle(DayTheme.accent) }
                if entry.day.unavailable { Text("Open Orbit to set up your planner.").font(.caption) }
                else {
                    Text(count == 7 ? "Your past week" : "Your past month").font(.caption).foregroundStyle(.secondary)
                    ConsistencyWidgetGrid(values: entry.day.consistency.isEmpty ? Array(repeating: 0, count: count) : Array(entry.day.consistency.suffix(count)))
                    Text("\(entry.day.completedHabits)/\(entry.day.totalHabits) checked today").font(.caption2).foregroundStyle(.secondary)
                }
            }.containerBackground(for: .widget) { Color(uiColor: .systemBackground) }.widgetURL(URL(string: "orbit://today"))
        }.configurationDisplayName("Habit consistency").description("Small steps, over a week or a month. Hold the widget and choose Edit Widget to change its range.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
