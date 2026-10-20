import SwiftUI
import SwiftData

/// Home layout is a device preference, never a destructive edit to planner data.
struct HomeLayoutEditor: View {
    @AppStorage("homeSections") private var stored = "consistency,progress,today,routine,completed,calendar"
    @AppStorage("hiddenHomeSections") private var hidden = ""
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Environment(\.dismiss) private var dismiss
    private var sections: [String] { stored.split(separator: ",").map(String.init) }
    static func title(_ id: String, lists: [TaskList]) -> String {
        switch id {
        case "consistency": return "Habit consistency"
        case "progress": return "Daily progress"
        case "today": return "For today"
        case "routine": return "Your routine"
        case "completed": return "Completed"
        case "calendar": return "From your calendars"
        default: return lists.first { "list:" + $0.id.uuidString == id }?.name ?? "List"
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Drag to arrange · switch off to hide") {
                    ForEach(sections, id: \.self) { id in
                        Toggle(Self.title(id, lists: lists), isOn: Binding(get: { !hidden.split(separator: ",").contains(Substring(id)) }, set: { visible in
                            var values = Set(hidden.split(separator: ",").map(String.init))
                            if visible { values.remove(id) } else { values.insert(id) }
                            hidden = values.sorted().joined(separator: ",")
                        }))
                    }.onMove { from, to in var values = sections; values.move(fromOffsets: from, toOffset: to); stored = values.joined(separator: ",") }
                }
                Section("Pin a list") {
                    ForEach(lists.filter { !sections.contains("list:" + $0.id.uuidString) }) { list in
                        Button(list.name, systemImage: "plus") { stored += ",list:" + list.id.uuidString }
                    }
                    Text("Pinned lists show their unfinished to-dos, including plans for later. Hiding a section keeps all your items.").font(.footnote).foregroundStyle(.secondary)
                }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle("Your Today").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ConsistencyStrip: View {
    let habits: [Habit]
    let logs: [HabitLog]
    @AppStorage("consistencyRange") private var range = 7
    private var days: [Date] { (0..<range).reversed().map { Calendar.current.date(byAdding: .day, value: -$0, to: .now)! } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Small steps add up").font(.subheadline.weight(.semibold))
                Spacer()
                Menu { Button("Past week") { range = 7 }; Button("Past month") { range = 30 } } label: {
                    Text(range == 7 ? "Week" : "Month").font(.caption)
                    Image(systemName: "chevron.down").font(.caption2)
                }.accessibilityLabel("Consistency range")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: range == 7 ? 7 : 10), spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let ratio = PlannerLogic.dailyConsistency(habits: habits, logs: logs, on: day)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 5).fill(DayTheme.accent.opacity(0.10))
                            .overlay(alignment: .bottom) { GeometryReader { proxy in
                                VStack { Spacer(minLength: 0); DayTheme.accent.frame(height: proxy.size.height * ratio) }
                            }.clipShape(RoundedRectangle(cornerRadius: 5)) }
                            .frame(height: range == 7 ? 30 : 20)
                        if range == 7 { Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary) }
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(Int(ratio * 100)) percent of habits")
                }
            }
            if habits.isEmpty { Text("Your habit check-ins will grow here.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct OrbitMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(DayTheme.accent)
            Circle().trim(from: 0, to: 0.75).stroke(.white, style: StrokeStyle(lineWidth: 4.5, lineCap: .round)).frame(width: 23, height: 23)
            Circle().fill(.white).frame(width: 6, height: 6).offset(x: 9, y: -9)
        }.frame(width: 48, height: 48).accessibilityHidden(true)
    }
}
