import SwiftUI

/// Native menu with an explicit value color, including inside grouped Forms.
struct AccentPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [(Value, String)]
    @Environment(\.orbitAccent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { Text(title); valueMenu }
        } else {
            HStack { Text(title); Spacer(); valueMenu }
        }
    }
    private var valueMenu: some View {
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
                }.foregroundStyle(accent.text).frame(minHeight: 44)
            }.accessibilityLabel(title).accessibilityValue(choices.first { $0.0 == selection }?.1 ?? "Choose")
    }
}
