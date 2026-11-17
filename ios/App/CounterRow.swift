import SwiftUI
import SwiftData
import UIKit

/// A counter: a habit with no target. Tapping anywhere on the row adds one for today, and the
/// number rolls up. Touch and hold for Take One Off, Edit and Delete; swipe right to edit, left to
/// delete. Counters never count as done, so they stay where they are.
struct CounterRow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.groupedRows) private var grouped
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("compactRows") private var compactRows = false
    let habit: Habit
    /// This counter's taps by day (PlannerLogic.countsByHabit), worked out once by the list.
    let counts: [String: Int]
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    @State private var pressed = false
    private var today: Int { counts[PlannerLogic.today] ?? 0 }
    private var color: Color { DayTheme.color(habit.color) }
    private var rowHeight: CGFloat { compactRows && !typeSize.isAccessibilitySize ? 44 : (grouped ? 50 : 56) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: grouped ? 0 : DayTheme.rowRadius, style: .continuous) }

    var body: some View {
        SwipeRow(radius: grouped ? 0 : DayTheme.rowRadius, edit: edit, remove: remove) { swipe in
            Button { if !swipe.takesTap() { add(1) } } label: {
                HStack(spacing: 0) {
                    ZStack {
                        Circle().strokeBorder(color.opacity(0.55), lineWidth: DesignTokens.rowTickRing)
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                    }
                    .frame(width: CGFloat(DesignTokens.rowTickLarge), height: CGFloat(DesignTokens.rowTickLarge))
                    .frame(width: 46, height: rowHeight)
                    .symbolEffect(.bounce, value: feedback)
                    Text(habit.title).font(.body).foregroundStyle(.primary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(today)").font(.body.weight(.semibold)).monospacedDigit()
                            .contentTransition(.numericText(value: Double(today)))
                            .animation(reduceMotion ? nil : .snappy, value: today)
                        Text("today").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.trailing, 14)
                }
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(RowPress(pressed: $pressed))
            .accessibilityLabel("Add one to \(habit.title)").accessibilityValue("\(today) today")
            .accessibilityIdentifier("counter-row")
            .background { RowHighlight(pressed: pressed) }
            .background(color.opacity(grouped ? 0 : 0.07))
            .background(Color.orbitSurface)
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous))
        .contextMenu {
            if today > 0 { Button("Take One Off", systemImage: "minus.circle") { add(-1) } }
            Button("Edit", systemImage: "pencil", action: edit)
            Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = habit.title }
            Divider()
            Button("Delete counter", systemImage: "trash", role: .destructive) {
                // The menu closes first; then the row leaves (see TaskActions.move).
                Task { try? await Task.sleep(for: MenuDismissal.pause); remove() }
            }
        }
        .modifier(MutationErrorModifier(error: $error))
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
    }

    private func add(_ amount: Int) {
        do {
            if amount > 0 { try Mutations.log(habit, at: PlannerLogic.todayDate, in: context); Sounds.play(.tick) }
            else { try Mutations.undoLog(habit, at: PlannerLogic.todayDate, in: context) }
            feedback += 1
        } catch { self.error = error.localizedDescription }
    }
    private func remove() {
        guard habit.modelContext != nil, !habit.isDeleted else { return }
        withAnimation(reduceMotion ? nil : .orbitFold) {
            do { try Conversions.remove(habit, in: context) } catch { context.rollback(); self.error = error.localizedDescription }
        }
    }
}

/// A counter's history: today, the last 7 days and its daily average, then a bar for each of the
/// last 7 days and the last 12 weeks shaded by how busy each day was.
struct CounterHistory: View {
    let habit: Habit
    let counts: [String: Int]
    var body: some View {
        let color = DayTheme.color(habit.color)
        let today = PlannerLogic.today
        let week = (0..<7).reversed().map { HabitRules.addDays(today, -$0) }
        let values = week.map { counts[$0] ?? 0 }
        let total = values.reduce(0, +), most = max(1, values.max() ?? 1)
        let grid = BoxGrid.days().map { PlannerLogic.dayKey($0) }
        let peak = max(1, grid.filter { $0 <= today }.map { counts[$0] ?? 0 }.max() ?? 1)
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceL)) {
            HStack(spacing: 8) {
                figure("\(values.last ?? 0)", "today")
                figure("\(total)", "last 7 days")
                figure(total == 0 ? "0" : String(format: "%.1f", Double(total) / 7), "a day")
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(week.enumerated()), id: \.offset) { index, key in
                    VStack(spacing: 4) {
                        Text("\(values[index])").font(.caption.weight(.semibold)).monospacedDigit()
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(values[index] == 0 ? 0.25 : 1))
                            .frame(height: 4 + 36 * CGFloat(values[index]) / CGFloat(most))
                        Text(weekdayLetter(key)).font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last 7 days: " + values.map(String.init).joined(separator: ", "))
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 12 weeks").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                BoxGrid(levels: grid.map { key -> Double? in key > today ? nil : Double(counts[key] ?? 0) / Double(peak) },
                        color: color, maximumCell: nil, timeline: 21)
            }
            .accessibilityElement(children: .combine).accessibilityLabel("\(habit.title), last 12 weeks")
        }
    }
    /// Day keys are floating calendar days, read in UTC as HabitRules does.
    private func weekdayLetter(_ key: String) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.narrow)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return (HabitRules.date(key) ?? .now).formatted(style)
    }
    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color.orbitTrack(DesignTokens.tintProgressTrack), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
