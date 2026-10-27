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

/// This month as a run of days, like a "31 days of…" tracker: the 1st at top left, the last day at
/// bottom right, filled row by row. Days still to come are outlines; today has a ring.
struct MonthGrid: View {
    /// One per day of the month; nil is a day still to come.
    let levels: [Double?]
    let color: Color
    var columns = 6
    /// Index of today in `levels`.
    var today: Int? = nil
    var gap: CGFloat = 3
    var body: some View {
        GeometryReader { proxy in
            let rows = max(1, (levels.count + columns - 1) / columns)
            let side = max(2, min((proxy.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                                  (proxy.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)))
            let radius = min(CGFloat(DesignTokens.gridRadius), side / 3)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < levels.count {
                                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                                Group {
                                    if let level = levels[index] {
                                        shape.fill(Color.orbitTrack(DesignTokens.tintGridTrack))
                                            .overlay {
                                                if level > 0 { shape.fill(color.opacity(DesignTokens.gridMinOpacity + (1 - DesignTokens.gridMinOpacity) * min(1, level))) }
                                            }
                                    } else {
                                        shape.strokeBorder(Color.orbitTrack(DesignTokens.tintGridTrack * 1.6), lineWidth: 1)
                                    }
                                }
                                .overlay { if index == today { shape.strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.5) } }
                                .frame(width: side, height: side)
                            }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
    }

    /// Daily values (oldest first, ending today) placed on this month's days.
    static func levels(_ values: [Double], now: Date = .now, calendar: Calendar = .current) -> (levels: [Double?], today: Int) {
        let today = calendar.startOfDay(for: now)
        guard let month = calendar.dateInterval(of: .month, for: now),
              let count = calendar.range(of: .day, in: .month, for: now)?.count else { return ([], 0) }
        let levels = (0..<count).map { offset -> Double? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: month.start) else { return nil }
            let ago = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: today).day ?? 0
            if ago < 0 { return nil }
            return ago < values.count ? values[values.count - 1 - ago] : 0
        }
        return (levels, calendar.component(.day, from: now) - 1)
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
    /// Six across on the small widget (like a paper tracker); wider sizes use fewer, longer rows.
    private var columns: Int { family == .systemSmall ? 6 : 11 }
    private var month: String { Date.now.formatted(.dateTime.month(.wide)) }
    private func monthGrid(_ values: [Double], color: Color) -> some View {
        let placed = MonthGrid.levels(values)
        return MonthGrid(levels: placed.levels, color: color, columns: columns, today: placed.today)
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
                        monthGrid(grid.values, color: DayTheme.color(grid.color))
                            .accessibilityLabel(grid.title + ", " + month)
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                header
                monthGrid(entry.consistency, color: DayTheme.accent)
                    .accessibilityLabel(summary + ", " + month)
            }
        }
    }
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(text: family == .systemSmall ? month : "Habits · " + month)
            Spacer()
            Text("\(entry.completedHabits)/\(entry.totalHabits)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
