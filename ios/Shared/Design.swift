import SwiftUI
import UIKit

extension Color {
    /// A colour from a 0xRRGGBB value.
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    /// A colour that follows light and dark appearance.
    init(_ pair: DesignTokens.Pair) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? pair.dark : pair.light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Colours, spacing and radii from DesignTokens (generated from shared/design-tokens.json).
enum DayTheme {
    static var sharedDefaults: UserDefaults? {
        (Bundle.main.object(forInfoDictionaryKey: "OrbitAppGroup") as? String).flatMap { UserDefaults(suiteName: $0) }
    }
    /// The accent chosen in Settings, read from the shared defaults for widgets and intents.
    static var storedAccentName: String {
        UserDefaults.standard.string(forKey: "accentTheme") ?? sharedDefaults?.string(forKey: "accentTheme") ?? "coral"
    }
    static var accent: Color { accentColor(storedAccentName) }
    static let accents = ["coral", "sage", "lavender", "honey"]
    /// Fills: ticks, progress, selection.
    static func accentColor(_ name: String) -> Color { Color(hex: DesignTokens.accentFill[name] ?? DesignTokens.accentFill["coral"]!) }
    /// Text and links in the accent colour, at 4.5:1 contrast in both appearances.
    static func accentText(_ name: String) -> Color { Color(DesignTokens.accentText[name] ?? DesignTokens.accentText["coral"]!) }
    // Habit and list palette keeps its stored names.
    static let colors = ["sage", "clay", "lavender", "honey"]
    static func color(_ name: String) -> Color { Color(hex: DesignTokens.palette[name] ?? DesignTokens.palette["sage"]!) }
    static func canvas(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? DesignTokens.canvas.dark : DesignTokens.canvas.light) }
    static let surface = Color(DesignTokens.surface)
    static let spacing = CGFloat(DesignTokens.spaceL)
    static let radius = CGFloat(DesignTokens.radiusCard)
    static let rowRadius = CGFloat(DesignTokens.radiusRow)
}

struct DayCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(DesignTokens.spaceM)) { content }
            .padding(CGFloat(DesignTokens.spaceXl)).frame(maxWidth: .infinity, alignment: .leading)
            .background(DayTheme.surface, in: RoundedRectangle(cornerRadius: DayTheme.radius, style: .continuous))
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

/// The accent chosen in Settings. RootView sets it from one @AppStorage value, so every view
/// updates as soon as it changes; widgets read `DayTheme.accent` from the shared defaults.
struct OrbitAccent: Equatable {
    var name: String
    var fill: Color { DayTheme.accentColor(name) }
    var text: Color { DayTheme.accentText(name) }
}
private struct OrbitAccentKey: EnvironmentKey { static let defaultValue = OrbitAccent(name: "coral") }
extension EnvironmentValues {
    var orbitAccent: OrbitAccent {
        get { self[OrbitAccentKey.self] }
        set { self[OrbitAccentKey.self] = newValue }
    }
}
