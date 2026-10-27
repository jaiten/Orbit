import SwiftUI

enum OrbitTab: String, CaseIterable, Identifiable {
    case today, tasks, notes, habits, calendar
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .tasks: return "checklist"
        case .notes: return "note.text"
        case .habits: return "repeat"
        case .calendar: return "calendar"
        }
    }
    static let defaultOrder = "today,tasks,notes,habits,calendar"
    static func ordered(_ value: String) -> [OrbitTab] {
        var result: [OrbitTab] = []
        for name in value.split(separator: ",") {
            if let tab = OrbitTab(rawValue: String(name)), !result.contains(tab) { result.append(tab) }
        }
        return result + allCases.filter { !result.contains($0) }
    }
}

struct NavigationLayoutEditor: View {
    @AppStorage("tabOrder") private var order = OrbitTab.defaultOrder
    var body: some View {
        List {
            Section("Drag to arrange") {
                ForEach(OrbitTab.ordered(order)) { tab in Label(tab.title, systemImage: tab.symbol) }
                    .onMove { from, to in
                        var tabs = OrbitTab.ordered(order)
                        tabs.move(fromOffsets: from, toOffset: to)
                        order = tabs.map(\.rawValue).joined(separator: ",")
                    }
            }
            Button("Restore default order") { order = OrbitTab.defaultOrder }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tab order")
    }
}
