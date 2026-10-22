import SwiftUI
import WidgetKit

/// Every Today style has a compact layout; choosing a style never silently selects another.
struct LockScreenTodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry

    var body: some View {
        Group {
            if entry.day.unavailable {
                Label("Open Orbit to set up", systemImage: "checklist").font(.caption)
            } else if entry.style == .grid {
                LockScreenHistoryView(day: entry.day, days: 7)
            } else if entry.style == .checklist {
                checklist
            } else {
                progress
            }
        }
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        .widgetURL(URL(string: "orbit://today"))
    }

    @ViewBuilder private var progress: some View {
        if family == .accessoryCircular {
            Gauge(value: Double(entry.day.doneToday), in: 0...Double(max(1, entry.day.totalToday))) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text("\(entry.day.doneToday)").monospacedDigit()
            }.gaugeStyle(.accessoryCircular)
                .accessibilityLabel("\(entry.day.doneToday) of \(entry.day.totalToday) done today")
        } else if family == .accessoryInline {
            Label("\(entry.day.doneToday)/\(entry.day.totalToday) done today", systemImage: "checkmark.circle")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today · \(entry.day.doneToday)/\(entry.day.totalToday) done").font(.headline).monospacedDigit()
                ProgressView(value: Double(entry.day.doneToday), total: Double(max(1, entry.day.totalToday)))
                Text(entry.day.items.first?.title ?? "Nothing left today").font(.caption).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var checklist: some View {
        if family == .accessoryInline {
            Label(entry.day.items.first?.title ?? "Nothing left today", systemImage: "checklist")
        } else if family == .accessoryCircular {
            if let item = entry.day.items.first {
                Button(intent: CompleteItemIntent(itemID: item.id, isHabit: item.habit)) {
                    VStack(spacing: 2) {
                        Image(systemName: "circle")
                        Text(item.title).font(.caption2).lineLimit(2)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(item.habit ? "Log" : "Complete") \(item.title)")
            } else {
                Label("All done", systemImage: "checkmark.circle").font(.caption2)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(entry.day.items.count) left today").font(.caption2.bold())
                if entry.day.items.isEmpty { Text("Nothing left today").font(.headline) }
                ForEach(entry.day.items.prefix(2)) { item in
                    HStack(spacing: 6) {
                        Button(intent: CompleteItemIntent(itemID: item.id, isHabit: item.habit)) {
                            Image(systemName: "circle").frame(width: 24, height: 20)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(item.habit ? "Log" : "Complete") \(item.title)")
                        Text(item.title).font(.caption).lineLimit(1)
                    }
                }
            }
        }
    }
}

/// Monochrome history for the Lock Screen, with the same week/month selection as Home Screen.
struct LockScreenHistoryView: View {
    @Environment(\.widgetFamily) private var family
    let day: DayEntry
    let days: Int
    private var values: [Double] {
        let history = Array(day.consistency.suffix(days))
        return Array(repeating: 0, count: max(0, days - history.count)) + history
    }
    private var summary: String { "\(day.completedHabits)/\(day.totalHabits) habits today" }
    var body: some View {
        Group {
            if family == .accessoryInline {
                Label(summary, systemImage: "square.grid.3x3.fill")
            } else if family == .accessoryCircular {
                VStack(spacing: 3) {
                    Text(days == 7 ? "Week" : "Month").font(.caption2)
                    boxes(columns: days == 7 ? 4 : 6, cell: days == 7 ? 8 : 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary).font(.caption.bold()).lineLimit(1)
                    boxes(columns: days == 7 ? 7 : 10, cell: days == 7 ? 12 : 7)
                }
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Habit history, past \(days) days. \(summary)")
    }
    private func boxes(columns: Int, cell: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 2), count: columns), alignment: .leading, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(value <= 0 ? 0.15 : 0.3 + min(1, value) * 0.7))
                    .frame(width: cell, height: cell)
            }
        }.fixedSize()
    }
}
