import SwiftUI

enum DayTheme {
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
        scheme == .dark ? Color(red: 0.09, green: 0.10, blue: 0.09) : Color(red: 0.97, green: 0.96, blue: 0.93)
    }
    static let spacing: CGFloat = 16
    static let radius: CGFloat = 20
}

struct DayCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(0.055) : .white.opacity(0.85),
                        in: RoundedRectangle(cornerRadius: DayTheme.radius))
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
