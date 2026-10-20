import SwiftUI
import SwiftData

/// Settings: appearance, accent, reminders, calendars, widgets and your data. Account has its own screen.
struct SettingsView: View {
    @Environment(\.orbitAccent) private var accent
    @ObservedObject private var sync = SyncService.shared
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { AccountView() } label: {
                        LabeledContent("Account", value: sync.email ?? "Not signed in")
                    }
                }
                AppearanceSection()
                RemindersSection(message: $message)
                CalendarsSection(message: $message)
                WidgetsSection()
                DataSection(message: $message)
                Section("About") {
                    Text("Works offline. Sync runs while Orbit is open; widget changes sync the next time you open it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.tint(accent.fill).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { SyncIndicator() } }
                .alert("Orbit", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK") { message = nil }
                } message: { Text(message ?? "") }
        }
    }
}

private struct AppearanceSection: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("accentTheme") private var accentTheme = "coral"
    var body: some View {
        Section("Appearance") {
            AccentPicker(title: "Appearance", selection: $appearance, choices: [("system", "System"), ("light", "Light"), ("dark", "Dark")])
            HStack {
                ForEach(DayTheme.accents, id: \.self) { name in
                    Button { accentTheme = name } label: {
                        VStack(spacing: 8) {
                            Circle().fill(DayTheme.accentColor(name)).frame(width: 34, height: 34)
                                .overlay { if accentTheme == name { Image(systemName: "checkmark").foregroundStyle(.white) } }
                            Text(name.capitalized).font(.caption2).foregroundStyle(.primary)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel(name.capitalized + (accentTheme == name ? ", selected" : ""))
                }
            }.padding(.vertical, 6)
        }
    }
}

private struct RemindersSection: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @AppStorage("generalCheckIn") private var checkIn = false
    @AppStorage("checkInMinutes") private var checkInMinutes = 1080
    @Binding var message: String?
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: checkInMinutes / 60, minute: checkInMinutes % 60, second: 0, of: .now)! }, set: { date in
            checkInMinutes = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
            Task { try? await refreshReminders(context) }
        })
    }
    var body: some View {
        Section {
            Button(action: allow) { Label { Text("Allow Notifications") } icon: { Image(systemName: "bell").foregroundStyle(accent.fill) } }
            Toggle("Daily check-in", isOn: $checkIn)
                .onChange(of: checkIn) { _, enabled in
                    Task { do { if enabled { _ = try await NotificationScheduler.shared.requestPermission() }; try await refreshReminders(context) } catch { message = error.localizedDescription } }
                }
            if checkIn {
                DatePicker("At", selection: time, displayedComponents: .hourAndMinute)
                Button("Use My Usual Time") { checkInMinutes = UsageSignals.suggestedMinutes(); Task { try? await refreshReminders(context) } }
            }
        } header: { Text("Reminders") } footer: {
            Text("Task and habit reminders, plus one optional daily check-in. The suggested time is based on when you usually open Orbit, counted on this device only.")
        }
    }
    private func allow() {
        Task {
            do {
                let granted = try await NotificationScheduler.shared.requestPermission()
                if granted { try await refreshReminders(context) }
                message = granted ? "Reminders are on." : "Notifications are off. You can turn them on in iOS Settings → Orbit → Notifications."
            } catch { message = error.localizedDescription }
        }
    }
}

private struct CalendarsSection: View {
    @Environment(\.orbitAccent) private var accent
    @ObservedObject private var calendars = CalendarBridge.shared
    @Binding var message: String?
    var body: some View {
        Section {
            if calendars.connected {
                Label("Calendars connected", systemImage: "checkmark.circle")
                Button("Disconnect Calendars") { calendars.disconnect() }
            } else {
                Button { Task { do { try await calendars.connect() } catch { message = error.localizedDescription } } } label: {
                    Label { Text("Connect Calendars") } icon: { Image(systemName: "calendar").foregroundStyle(accent.fill) }
                }
            }
        } header: { Text("Calendars") } footer: { Text("Shows events from Apple Calendar, including Google accounts added to your iPhone.") }
    }
}

private struct WidgetsSection: View {
    @AppStorage("consistencyRange") private var consistencyRange = 7
    var body: some View {
        Section {
            AccentPicker(title: "History range", selection: $consistencyRange, choices: [(7, "Past week"), (30, "Past month")])
        } header: { Text("Widgets") } footer: { Text("Also used on Today. Each widget can override it with Edit Widget.") }
    }
}

private struct DataSection: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [PlannerTask]
    @Query private var habits: [Habit]
    @Binding var message: String?
    private var hasExamples: Bool {
        tasks.contains { Examples.taskIDs.contains($0.id) } || habits.contains { Examples.habitIDs.contains($0.id) }
    }
    var body: some View {
        Section {
            NavigationLink("Import & Export") { BackupView() }
            if hasExamples {
                Button("Remove Examples") {
                    do { try Examples.remove(in: context); Task { try? await refreshReminders(context) } } catch { message = error.localizedDescription }
                }
            }
        } header: { Text("Data") } footer: {
            if hasExamples { Text("Removes the example tasks, list and habits. Anything you added stays.") }
        }
    }
}
