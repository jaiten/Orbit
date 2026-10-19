import SwiftUI

enum DayTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.48, blue: 0.43, alpha: 1)
            : UIColor(red: 0.77, green: 0.23, blue: 0.20, alpha: 1)
    })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
    })
    static let sage = Color(red: 0.38, green: 0.48, blue: 0.36)
    static let clay = Color(red: 0.72, green: 0.43, blue: 0.32)
    static let lavender = Color(red: 0.57, green: 0.50, blue: 0.67)
    static let honey = Color(red: 0.70, green: 0.53, blue: 0.23)
    static let colors = ["sage", "clay", "lavender", "honey"]
    static func color(_ name: String) -> Color {
        switch name { case "clay": return clay; case "lavender": return lavender
        case "honey": return honey; default: return sage }
    }
    static func canvas(_ scheme: ColorScheme) -> Color {
        Color(uiColor: .systemGroupedBackground)
    }
    static let spacing: CGFloat = 16
    static let radius: CGFloat = 20
}

struct DayCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DayTheme.surface, in: RoundedRectangle(cornerRadius: DayTheme.radius, style: .continuous))
    }
}

struct ProgressRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double
    var color: Color = DayTheme.accent
    var lineWidth: CGFloat = 5
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: value)
        .accessibilityHidden(true)
    }
}

/// A single compact week strip shared by Today and the planner.
struct WeekStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation
    @Binding var selection: Date
    var markedDays: Set<String> = []
    var today: Date = .now
    var onDrop: (([String], Date) -> Bool)?
    private var days: [Date] {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: selection)!.start
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let selected = Calendar.current.isDate(day, inSameDayAs: selection)
                let current = Calendar.current.isDate(day, inSameDayAs: today)
                Button { selection = day } label: {
                    VStack(spacing: 7) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.subheadline.weight(selected || current ? .semibold : .regular))
                            .foregroundStyle(selected ? DayTheme.onAccent : (current ? DayTheme.accent : Color.primary))
                            .frame(width: 34, height: 34)
                            .background {
                                if selected {
                                    Circle().fill(DayTheme.accent).matchedGeometryEffect(id: "selectedDay", in: selectionAnimation)
                                }
                            }
                        Circle().fill(markedDays.contains(PlannerLogic.dayKey(day)) ? DayTheme.accent : .clear)
                            .frame(width: 4, height: 4)
                    }.frame(maxWidth: .infinity).padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .dropDestination(for: String.self) { ids, _ in onDrop?(ids, day) ?? false }
            }
        }.animation(reduceMotion ? nil : .smooth(duration: 0.22), value: selection)
    }
}

struct QuietEmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
