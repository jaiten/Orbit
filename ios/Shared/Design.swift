import SwiftUI

enum DayTheme {
    /// Single UI accent: a soft coral, used sparingly against neutral surfaces.
    static let accent = Color(red: 0.91, green: 0.45, blue: 0.36)
    // Habit palette keeps its stored names; values are muted to sit quietly on neutrals.
    static let sage = Color(red: 0.43, green: 0.55, blue: 0.47)
    static let clay = Color(red: 0.85, green: 0.48, blue: 0.40)
    static let lavender = Color(red: 0.55, green: 0.52, blue: 0.75)
    static let honey = Color(red: 0.82, green: 0.62, blue: 0.30)
    static let colors = ["sage", "clay", "lavender", "honey"]
    static func color(_ name: String) -> Color {
        switch name { case "clay": return clay; case "lavender": return lavender
        case "honey": return honey; default: return sage }
    }
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.09) : Color(red: 0.96, green: 0.96, blue: 0.97)
    }
    static let spacing: CGFloat = 16
    static let radius: CGFloat = 18
}

struct DayCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(0.06) : .white,
                        in: RoundedRectangle(cornerRadius: DayTheme.radius, style: .continuous))
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
