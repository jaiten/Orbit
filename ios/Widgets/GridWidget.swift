import SwiftUI
import WidgetKit

/// One habit's daily progress for the large Grid widget, oldest day first and today last.
struct HabitGrid: Identifiable {
    let id: String
    let title: String
    let color: String
    let values: [Double]
}

/// GitHub-style boxes: a column per week, a row per weekday, today in the last column.
/// It fits as many weeks as the width allows, so one view serves every widget size.
struct ActivityGrid: View {
    /// Daily progress from 0 to 1, oldest first; the last value is today.
    let values: [Double]
    let color: Color
    var cell: CGFloat = 10
    var spacing: CGFloat = 3
    var label = "Habit history"
    var body: some View {
        GeometryReader { proxy in
            let weeks = max(1, Int((proxy.size.width + spacing) / (cell + spacing)))
            let shown = (weeks - 1) * 7 + Self.weekdayIndex(.now) + 1
            let days = Array(repeating: 0.0, count: max(0, shown - values.count)) + values.suffix(shown)
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let index = week * 7 + weekday
                            RoundedRectangle(cornerRadius: cell * 0.25, style: .continuous)
                                .fill(index < days.count ? shade(days[index]) : .clear)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: cell * 7 + spacing * 6)
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
    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular:
            ActivityGrid(values: entry.consistency, color: .primary, cell: 6, spacing: 2, label: summary)
        case .systemLarge where !entry.grids.isEmpty:
            VStack(alignment: .leading, spacing: 10) {
                header
                ForEach(entry.grids.prefix(3)) { grid in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(grid.title).font(.caption.weight(.semibold)).lineLimit(1)
                        ActivityGrid(values: grid.values, color: DayTheme.color(grid.color), cell: 8, spacing: 2, label: grid.title + " history")
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                header
                Spacer(minLength: 0)
                ActivityGrid(values: entry.consistency, color: DayTheme.accent, label: summary)
            }
        }
    }
    private var header: some View {
        HStack {
            Text("Habits").font(.headline)
            Spacer()
            Text("\(entry.completedHabits)/\(entry.totalHabits) today").font(.caption).foregroundStyle(.secondary)
        }
    }
}
