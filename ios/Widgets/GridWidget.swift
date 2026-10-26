import SwiftUI
import WidgetKit

/// One habit's daily progress for the large Grid widget, oldest day first and today last.
struct HabitGrid: Identifiable {
    let id: String
    let title: String
    let color: String
    let values: [Double]
}

/// Compact calendar boxes: seven days across, then the next week below.
struct ActivityGrid: View {
    /// Daily progress from 0 to 1, oldest first; the last value is today.
    let values: [Double]
    let color: Color
    var cell: CGFloat = 10
    var spacing: CGFloat = 3
    var label = "Habit history"
    var body: some View {
        GeometryReader { proxy in
            let rows = max(1, Int((proxy.size.height + spacing) / (cell + spacing)))
            let shown = (rows - 1) * 7 + Self.weekdayIndex(.now) + 1
            let days = Array(repeating: 0.0, count: max(0, shown - values.count)) + values.suffix(shown)
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(0..<rows, id: \.self) { week in
                    HStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let index = week * 7 + weekday
                            RoundedRectangle(cornerRadius: cell * 0.25, style: .continuous)
                                .fill(index < days.count ? shade(days[index]) : .clear)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(label)
    }
    /// The same five levels as Today's grid: empty, then lighter to full colour.
    private func shade(_ value: Double) -> Color {
        let level = value <= 0 ? 0 : value < 0.34 ? 1 : value < 0.67 ? 2 : value < 1 ? 3 : 4
        return color.opacity([0.14, 0.35, 0.55, 0.78, 1][level])
    }
    /// 0 for the first day of the week in this locale, up to 6.
    static func weekdayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
    }
}

struct GridWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry
    var body: some View {
        content.containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
            .widgetURL(URL(string: "orbit://today"))
    }
    private var summary: String { "\(entry.completedHabits) of \(entry.totalHabits) habits checked today" }
    /// Calendar rows per size. Wide widgets need fewer rows; large widgets show one compact
    /// calendar for each habit.
    private var weeks: Int { family == .systemSmall ? 7 : family == .systemMedium ? 3 : 2 }
    /// Daily values (oldest first, ending today) laid out in whole weeks; days still to come are nil.
    private func levels(_ values: [Double]) -> [Double?] {
        let today = Calendar.current.startOfDay(for: .now)
        return BoxGrid.days(weeks: weeks).map { day -> Double? in
            let ago = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: day), to: today).day ?? 0
            if ago < 0 { return nil }
            return ago < values.count ? values[values.count - 1 - ago] : 0
        }
    }
    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular:
            ActivityGrid(values: entry.consistency, color: .primary, cell: 6, spacing: 2, label: summary)
        case .systemLarge where !entry.grids.isEmpty:
            VStack(alignment: .leading, spacing: 12) {
                header
                ForEach(entry.grids.prefix(3)) { grid in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(grid.title).font(.footnote).lineLimit(1)
                        BoxGrid(levels: levels(grid.values), color: DayTheme.color(grid.color), weeks: weeks, gap: 2, maximumCell: nil)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .accessibilityLabel(grid.title + " history")
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                header
                BoxGrid(levels: levels(entry.consistency), color: DayTheme.accent, weeks: weeks, gap: 2, maximumCell: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .accessibilityLabel(summary)
            }
        }
    }
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(text: "Habits")
            Spacer()
            Text(family == .systemSmall ? "\(entry.completedHabits)/\(entry.totalHabits)" : "Last \(weeks) weeks").font(.caption).foregroundStyle(.secondary)
        }
    }
}
