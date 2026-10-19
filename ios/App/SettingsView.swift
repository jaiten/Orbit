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
    @ObservedObject private var sync = SyncService.shared
    @Query private var syncEntries: [SyncEntry]
    @State private var email = ""
    @State private var password = ""
    @State private var signingIn = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Orbit").font(.largeTitle.weight(.bold))
                    Text("A little space for what matters.").foregroundStyle(.secondary)
                    Label(sync.status, systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Across your devices") {
                    if let account = sync.email {
                        Text(account)
                        Button("Sync now") { Task { await sync.run(context) } }
                        Button("Sign out") { do { try sync.signOut() } catch { message = error.localizedDescription } }
                    } else {
                        TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(.password)
                        Button("Sign in") { authenticate(create: false) }.disabled(signingIn || email.isEmpty || password.isEmpty)
                        Button("Create account") { authenticate(create: true) }.disabled(signingIn || email.isEmpty || password.count < 8)
                        Text("Sign in on your PC with the same account. Your existing planner will be added to that account and stay available offline.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(syncEntries.filter { $0.conflict != nil }) { entry in
                    Section("Choose which change to keep") {
                        Text((try? SyncRecords.object(entry.payload)["title"] as? String) ?? entry.key)
                        DisclosureGroup("Compare versions") {
                            Text("This device: " + entry.payload).font(.caption)
                            Text("Other device: " + (entry.conflict ?? "")).font(.caption)
                        }
                        Button("Keep this device") { resolve(entry, local: true) }
                        Button("Keep other device") { resolve(entry, local: false) }
                    }
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
                    Text("Offline first. Sign in to share your planner with Orbit for Windows. Sync runs while the app is open; widget changes sync when you reopen Orbit.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
                .alert("Orbit", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK") { message = nil }
                } message: { Text(message ?? "") }
        }
    }
    private func authenticate(create: Bool) {
        signingIn = true
        Task {
            defer { signingIn = false }
            do { message = try await sync.signIn(email: email, password: password, create: create, context: context); password = "" }
            catch { message = error.localizedDescription }
        }
    }
    private func resolve(_ entry: SyncEntry, local: Bool) {
        Task { do { try await sync.resolve(entry, local: local, context: context) } catch { message = error.localizedDescription } }
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
