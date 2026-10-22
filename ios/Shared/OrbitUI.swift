import SwiftUI

// The building blocks of the website's app screens, shared by the app and its widgets.
// Sizes, tints and springs come from DesignTokens (shared/design-tokens.json). Fonts are
// text styles so Dynamic Type still scales: caption2 is the 11pt eyebrow, title2 the 22pt
// plan count, subheadline the 15pt section title and footnote the 13pt detail.

extension Animation {
    /// Rows, chips and buttons.
    static var orbit: Animation { .spring(response: DesignTokens.springUi.response, dampingFraction: DesignTokens.springUi.damping) }
    /// Livelier, for presses.
    static var orbitLift: Animation { .spring(response: DesignTokens.springLift.response, dampingFraction: DesignTokens.springLift.damping) }
    /// Large elements and progress.
    static var orbitSoft: Animation { .spring(response: DesignTokens.springSoft.response, dampingFraction: DesignTokens.springSoft.damping) }
}

extension Color {
    static let orbitLine = Color(DesignTokens.line)
    static let orbitSurface = Color(DesignTokens.surface)
    /// Ink at a small strength, for tracks under progress and grids.
    static func orbitTrack(_ strength: Double) -> Color { Color(DesignTokens.ink).opacity(strength) }
}

/// Tiny uppercase label above cards and sections ("YOUR PLAN").
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(DesignTokens.typeEyebrow * DesignTokens.typeEyebrowTracking)
            .foregroundStyle(.secondary).lineLimit(1)
    }
}

/// Eyebrow, large title (tight tracking) and a muted subtitle, with small tools on the right.
struct PageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle = ""
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize
    init(eyebrow: String, title: String, subtitle: String = "", @ViewBuilder trailing: () -> Trailing) {
        self.eyebrow = eyebrow; self.title = title; self.subtitle = subtitle; self.trailing = trailing()
    }
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { heading; tools }
            } else {
                HStack(alignment: .top) { heading; Spacer(minLength: 8); tools }
            }
        }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(title).font(.largeTitle.bold()).tracking(-1).accessibilityAddTraits(.isHeader)
            if !subtitle.isEmpty { Text(subtitle).font(.body).foregroundStyle(.secondary) }
        }
    }
    private var tools: some View {
        HStack(spacing: 2) { trailing }.font(.body).foregroundStyle(.secondary).buttonStyle(.plain)
    }
}
extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String = "") { self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() } }
}

/// A section title with a tiny uppercase note on the right ("Habits · REPEATS").
struct SectionLabel: View {
    let title: String
    var note = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            if !note.isEmpty { Text(note.uppercased()).font(.caption2.weight(.medium)).tracking(0.9).foregroundStyle(.secondary) }
        }.padding(.horizontal, 4).accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

/// Surface with a 1px line instead of a shadow, at row (12) or card (18) radius.
struct OrbitSurface: ViewModifier {
    var radius = CGFloat(DesignTokens.radiusRow)
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background(Color.orbitSurface, in: shape).overlay(shape.strokeBorder(Color.orbitLine, lineWidth: 1))
    }
}
extension View {
    func orbitSurface(radius: CGFloat = CGFloat(DesignTokens.radiusRow)) -> some View { modifier(OrbitSurface(radius: radius)) }
    func orbitCard() -> some View { padding(18).frame(maxWidth: .infinity, alignment: .leading).modifier(OrbitSurface(radius: CGFloat(DesignTokens.radiusCard))) }
}

/// Press feedback: a small spring scale.
struct OrbitPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.985 : 1).animation(.orbitLift, value: configuration.isPressed)
    }
}

private struct TickMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.21, y: rect.height * 0.52))
        p.addLine(to: CGPoint(x: rect.width * 0.4, y: rect.height * 0.71))
        p.addLine(to: CGPoint(x: rect.width * 0.79, y: rect.height * 0.31))
        return p
    }
}

/// Round checkbox: a 2pt ring at 45%; done fills it, draws a white tick (280ms) and pops 1 → 1.14 → 1.
struct OrbitTick: View {
    let done: Bool
    var color: Color
    var size = CGFloat(DesignTokens.rowTickLarge)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 1
    var body: some View {
        ZStack {
            Circle().strokeBorder(done ? color : color.opacity(DesignTokens.tintTickRing), lineWidth: DesignTokens.rowTickRing)
            Circle().fill(color).scaleEffect(done ? 1 : 0.6).opacity(done ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .orbit, value: done)
            TickMark().trim(from: 0, to: done ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: max(2, size * 0.12), lineCap: .round, lineJoin: .round))
                .padding(size * 0.08)
                .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.tickDrawSeconds).delay(done ? 0.08 : 0), value: done)
        }
        .frame(width: size, height: size).scaleEffect(pop)
        .onChange(of: done) { _, now in
            guard now, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.16)) { pop = DesignTokens.tickPop } completion: { withAnimation(.orbit) { pop = 1 } }
        }
        .accessibilityHidden(true)
    }
}

/// "Your plan": the day's count at 22pt and a 6pt bar that fills with a soft spring.
struct PlanCard: View {
    let done: Int
    let total: Int
    var accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "Your plan")
            Text("\(done) of \(total) done").font(.title2.weight(.medium)).tracking(-0.4).monospacedDigit()
            Capsule().fill(Color.orbitTrack(DesignTokens.tintProgressTrack)).frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(accent).frame(width: proxy.size.width)
                            .scaleEffect(x: total == 0 ? 0 : CGFloat(done) / CGFloat(total), anchor: .leading)
                    }
                }.clipShape(Capsule()).padding(.top, 8)
                .animation(reduceMotion ? nil : .orbitSoft, value: done)
        }
        .orbitCard()
        .accessibilityElement(children: .ignore).accessibilityLabel("Your plan: \(done) of \(total) done")
    }
}

/// GitHub-style boxes: a column per week, a row per day, oldest first. Boxes stay square and are
/// sized to whichever runs out first, the width or the height. A nil level is a day still to come.
struct BoxGrid: View {
    let levels: [Double?]
    let color: Color
    var weeks = DesignTokens.gridWeeks
    var gap = CGFloat(DesignTokens.gridGap)
    var body: some View {
        GeometryReader { proxy in
            let side = max(2, min((proxy.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks), (proxy.size.height - gap * 6) / 7))
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { day in
                            let index = week * 7 + day
                            let level = index < levels.count ? levels[index] : nil
                            RoundedRectangle(cornerRadius: min(CGFloat(DesignTokens.gridRadius), side / 3), style: .continuous)
                                .fill(level == nil ? Color.clear : Color.orbitTrack(DesignTokens.tintGridTrack))
                                .overlay {
                                    if let level, level > 0 {
                                        RoundedRectangle(cornerRadius: min(CGFloat(DesignTokens.gridRadius), side / 3), style: .continuous)
                                            .fill(color.opacity(DesignTokens.gridMinOpacity + (1 - DesignTokens.gridMinOpacity) * min(1, level)))
                                    }
                                }
                                .frame(width: side, height: side)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .aspectRatio(CGFloat(weeks) / 7, contentMode: .fit)
        .accessibilityElement(children: .ignore)
    }
    /// Days for the grid: whole weeks in the locale's order, ending with this week.
    static func days(weeks: Int = DesignTokens.gridWeeks, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisWeek) ?? thisWeek
        return (0..<(weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }
}

/// "5 of the last 7 days" as seven rounded segments, with weekday letters below.
struct WeekSegments: View {
    let done: [Bool]
    let days: [Date]
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(zip(done, days).enumerated()), id: \.offset) { _, pair in
                VStack(spacing: 6) {
                    Capsule().fill(pair.0 ? color : Color.orbitTrack(DesignTokens.tintProgressTrack)).frame(height: 10)
                    Text(pair.1.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done.filter { $0 }.count) of the last 7 days")
    }
}

/// A readable preview that wraps with larger text and long list names.
struct PreviewChip: View {
    let text: String
    var identifier = "quick-add-preview"
    @Environment(\.orbitAccent) private var accent
    var body: some View {
        if !text.isEmpty {
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(accent.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(accent.fill.opacity(DesignTokens.tintAccentFill), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier(identifier)
        }
    }
}

/// The quiet field that opens quick add.
struct AddField: View {
    @Environment(\.orbitAccent) private var accent
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.subheadline.weight(.medium)).foregroundStyle(accent.text)
                Text("Add a task").font(.subheadline)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary).padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 48).contentShape(Rectangle()).orbitSurface()
        }
        .buttonStyle(OrbitPress()).accessibilityLabel("Add a task")
    }
}
