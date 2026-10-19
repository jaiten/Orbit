import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearance = "system"
    @Query private var tasks: [PlannerTask]
    @Query private var habits: [Habit]
    @Query(sort: \IdeaPrompt.updatedAt) private var ideas: [IdeaPrompt]
    @State private var ideaText = ""
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Orbit").font(.largeTitle.weight(.bold))
                    Text("Habits. Tasks. A little more focus.").foregroundStyle(.secondary)
                    Label("Saved on this device", systemImage: "internaldrive").foregroundStyle(DayTheme.sage)
                }
                Section("Preferences") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    Button("Enable reminders", systemImage: "bell") {
                        Task {
                            do {
                                let granted = try await NotificationScheduler.shared.requestPermission()
                                if granted { try await refreshReminders(context) }
                                message = granted ? "Reminders are enabled." : "Notifications are off. You can enable them in iOS Settings → Orbit → Notifications."
                            } catch { message = error.localizedDescription }
                        }
                    }
                }
                Section {
                    TextField("Something you’d like to try", text: $ideaText, axis: .vertical)
                    Button("Add to my ideas") {
                        context.insert(IdeaPrompt(text: ideaText.trimmingCharacters(in: .whitespacesAndNewlines)))
                        do { try Mutations.save(context); ideaText = "" } catch { message = error.localizedDescription }
                    }.disabled(ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(ideas) { idea in
                        HStack {
                            Text(idea.text).foregroundStyle(idea.dismissed ? .secondary : .primary)
                            Spacer()
                            if idea.dismissed {
                                Button("Restore") { idea.dismissed = false; idea.updatedAt = .now
                                    do { try Mutations.save(context) } catch { message = error.localizedDescription }
                                }.font(.caption)
                            }
                        }
                    }.onDelete { offsets in
                        for index in offsets { context.delete(ideas[index]) }
                        do { try Mutations.save(context) } catch { message = error.localizedDescription }
                    }
                } header: { Text("Try something new") } footer: { Text("One of your ideas appears on Today each day. Always written by you.") }
                if tasks.isEmpty && habits.isEmpty {
                    Section { Button("Explore with sample data", action: seed) }
                }
                Section("About this prototype") {
                    Text("Offline first. No account, subscription, or feature caps. Sync and the Windows client are planned for the next phase.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
                .alert("Orbit", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK") { message = nil }
                } message: { Text(message ?? "") }
        }
    }
    private func seed() {
        let personal = TaskList(name: "Personal", color: "sage")
        context.insert(personal)
        for (index, value) in [("Morning walk", 8), ("Focus on one meaningful thing", 10), ("Make something nourishing", 18)].enumerated() {
            let date = Calendar.current.date(bySettingHour: value.1, minute: 0, second: 0, of: .now)!
            let task = PlannerTask(title: value.0, dueDate: date, hasTime: true, listID: personal.id)
            task.sortOrder = index; context.insert(task)
        }
        let task = PlannerTask(title: "Call someone you miss", listID: personal.id); task.sortOrder = 3; context.insert(task)
        context.insert(Habit(title: "Read a few pages", color: "lavender", icon: "book"))
        context.insert(Habit(title: "Drink water", target: 6, color: "sage", icon: "drop"))
        context.insert(Habit(title: "Move your body", frequencyRule: "WEEKLY", target: 3, color: "clay", icon: "figure.walk"))
        do { try Mutations.save(context) } catch { message = error.localizedDescription }
    }
}
