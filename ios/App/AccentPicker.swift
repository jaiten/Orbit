import SwiftUI

/// Native menu with an explicit value color, including inside grouped Forms.
struct AccentPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [(Value, String)]
    @AppStorage("accentTheme") private var accentTheme = "coral"
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    Button { selection = choice.0 } label: {
                        if choice.0 == selection { Label(choice.1, systemImage: "checkmark") }
                        else { Text(choice.1) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(choices.first { $0.0 == selection }?.1 ?? "Choose")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }.foregroundStyle(DayTheme.accentColor(accentTheme)).frame(minHeight: 36)
            }.accessibilityLabel(title).accessibilityValue(choices.first { $0.0 == selection }?.1 ?? "Choose")
        }
    }
}
