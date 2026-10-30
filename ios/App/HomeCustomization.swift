import SwiftUI
import SwiftData

/// Home layout is a device preference, never a destructive edit to planner data.
struct HomeLayoutEditor: View {
    @Environment(\.orbitAccent) private var accent
    /// The plan card, then the day's tasks and habits; history follows the actionable lists.
    static let defaultSections = "consistency,today,routine,completed,calendar,progress"
    static let defaultHidden = "progress"

    /// Upgrade only the previous default profile. Preserve customized orders, pins and visibility.
    static func upgradedLayout(sections: String, hidden: String) -> (sections: String, hidden: String) {
        let original = sections == "progress,today,routine,completed,calendar,consistency" && hidden == "consistency"
        let previous = sections == "progress,routine,today,completed,consistency,calendar" && hidden.isEmpty
        let habitsFirst = sections == "routine,today,completed,calendar,progress,consistency" && hidden == "progress,consistency"
        guard original || previous || habitsFirst else { return (sections, hidden) }
        return (defaultSections, defaultHidden)
    }
    @AppStorage("homeSections") private var stored = defaultSections
    @AppStorage("hiddenHomeSections") private var hidden = defaultHidden
    @AppStorage("showOverallProgress") private var showOverall = false
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Environment(\.dismiss) private var dismiss
    private var sections: [String] { let values = stored.split(separator: ",").map(String.init); return values.contains("overall") ? values : values + ["overall"] }
    static func title(_ id: String, lists: [TaskList]) -> String {
        switch id {
        case "consistency": return "Recent progress"
        case "overall": return "Overall progress"
        case "progress": return "Your plan"
        case "today": return "Your day"
        case "routine": return "Habits"
        case "completed": return "Completed"
        case "calendar": return "Calendar"
        default: return lists.first { "list:" + $0.id.uuidString == id }?.name ?? "List"
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Drag to arrange · switch off to hide") {
                    ForEach(sections, id: \.self) { id in
                        Toggle(Self.title(id, lists: lists), isOn: Binding(get: { id == "overall" ? showOverall : !hidden.split(separator: ",").contains(Substring(id)) }, set: { visible in
                            if id == "overall" { showOverall = visible; return }
                            var values = Set(hidden.split(separator: ",").map(String.init))
                            if visible { values.remove(id) } else { values.insert(id) }
                            hidden = values.sorted().joined(separator: ",")
                        }))
                    }.onMove { from, to in var values = sections; values.move(fromOffsets: from, toOffset: to); stored = values.joined(separator: ",") }
                }
                Section("Pin a list") {
                    ForEach(lists.filter { $0.isTaskCategory && !sections.contains("list:" + $0.id.uuidString) }) { list in
                        Button(list.name, systemImage: "plus") { stored += ",list:" + list.id.uuidString }
                    }
                    Text("Pinned lists show their unfinished tasks. Hiding a section never deletes anything.").font(.footnote).foregroundStyle(.secondary)
                }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle("Edit Today").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ConsistencyStrip: View {
    @Environment(\.orbitAccent) private var accent
    let habits: [Habit]
    let logs: [HabitLog]
    var selectedDate: Date = .now
    var selectDay: (Date) -> Void = { _ in }
    private let range = 7
    @AppStorage("progressIncludesTasks") private var includeTasks = true
    @Query private var tasks: [PlannerTask]
    private var days: [Date] { (0..<range).reversed().map { Calendar.current.date(byAdding: .day, value: -$0, to: .now)! } }
    var body: some View {
        let fractions = PlannerLogic.consistencySeries(habits: habits, logs: logs, ending: .now, days: range, tasks: tasks, includeTasks: includeTasks)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent progress").font(.subheadline.weight(.semibold))
                Spacer()

            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: range == 7 ? 7 : 10), spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let ratio = fractions[index]
                    Button { selectDay(day) } label: { VStack(spacing: 4) {
                        Circle().fill(accent.fill.opacity(0.08))
                            .overlay {
                                if ratio >= 1 { Circle().stroke(accent.fill, lineWidth: 3) }
                                else { Circle().trim(from: 0, to: ratio).stroke(accent.fill, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)) }
                            }.overlay {
                                if Calendar.current.isDate(day, inSameDayAs: selectedDate) {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent.text)
                                }
                            }.frame(width: range == 7 ? 30 : 20, height: range == 7 ? 30 : 20)
                        if range == 7 { Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(Int(ratio * 100)) percent complete. Edit this day")
                    .accessibilityIdentifier("progress-day-" + PlannerLogic.dayKey(day))
                    .accessibilityAddTraits(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? .isSelected : [])
                }
            }
        }
    }
}

struct OrbitMark: View {
    @Environment(\.orbitAccent) private var accent
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(accent.fill)
            Circle().trim(from: 0, to: 0.75).stroke(.white, style: StrokeStyle(lineWidth: 4.5, lineCap: .round)).frame(width: 23, height: 23)
            Circle().fill(.white).frame(width: 6, height: 6).offset(x: 9, y: -9)
        }.frame(width: 48, height: 48).accessibilityHidden(true)
    }
}

struct OverallProgressCard: View {
    let habits: [Habit]
    let logs: [HabitLog]
    let tasks: [PlannerTask]
    @AppStorage("overallProgressRange") private var range = 30
    @AppStorage("progressIncludesTasks") private var includesTasks = true
    @Environment(\.orbitAccent) private var accent
    var body: some View {
        let count = range == 7 ? 7 : 30
        let fractions = PlannerLogic.consistencySeries(habits: habits, logs: logs, ending: .now, days: count, tasks: tasks, includeTasks: includesTasks)
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Overall progress").font(.subheadline.weight(.semibold)); Spacer(); Text(count == 7 ? "Past week" : "Past month").font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(Array(fractions.enumerated()), id: \.offset) { index, value in
                    let date = Calendar.current.date(byAdding: .day, value: index - count + 1, to: .now)!
                    RoundedRectangle(cornerRadius: 4).fill(accent.fill.opacity(value == 0 ? 0.08 : 0.25 + 0.75 * value))
                        .frame(height: 28).overlay { Text(date.formatted(.dateTime.day())).font(.caption2).foregroundStyle(value > 0.8 ? Color.white : Color.secondary) }
                        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), \(Int(value * 100)) percent complete")
                }
            }
        }.orbitCard()
    }
}
