import SwiftUI
import SwiftData

/// Settings: appearance, accent, reminders, calendars, widgets and your data. Account has its own screen.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.orbitAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var sync = SyncService.shared
    @State private var message: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: CGFloat(DesignTokens.spaceL)) {
                PageHeader(eyebrow: "Preferences", title: "Settings") { SyncIndicator(textOnly: true) }
                    .padding(.horizontal, 20).padding(.top, 8)
                Form {
                    Section {
                        NavigationLink { AccountView() } label: {
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Account")
                                    Text(sync.email ?? "Sign in").foregroundStyle(.secondary)
                                }.fixedSize(horizontal: false, vertical: true)
                            } else {
                                LabeledContent("Account", value: sync.email ?? "Sign in")
                            }
                        }
                    }
                    Section("Layout") {
                        NavigationLink("Arrange Today") { HomeLayoutEditor() }
                        NavigationLink("Tab order") { NavigationLayoutEditor() }
                    }
                    AppearanceSection()
                    ProgressSection()
                    RemindersSection(message: $message)
                    CalendarsSection(message: $message)

                    DataSection(message: $message)
                    Section("About") {
                        Text("Works offline. Sync runs while Orbit is open; widget changes sync the next time you open it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.contentMargins(.top, 0, for: .scrollContent).listSectionSpacing(CGFloat(DesignTokens.spaceL))
                .scrollContentBackground(.hidden).background(DayTheme.canvas(scheme))
            }.frame(maxWidth: 760).frame(maxWidth: .infinity).background(DayTheme.canvas(scheme))
                .tint(accent.fill).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .alert("Orbit", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK") { message = nil }
                } message: { Text(message ?? "") }
        }
    }
}

private struct AppearanceSection: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @AppStorage("compactRows") private var compactRows = false
    var body: some View {
        Section("Appearance") {
            AccentPicker(title: "Appearance", selection: $appearance, choices: [("system", "System"), ("light", "Light"), ("dark", "Dark")])
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 12) {
                ForEach(DayTheme.accents, id: \.self) { name in
                    Button { accentTheme = name } label: {
                        VStack(spacing: 8) {
                            Circle().fill(DayTheme.accentColor(name)).frame(width: 34, height: 34)
                                .overlay { if accentTheme == name { Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white) } }
                            Text(name.capitalized).font(.caption2).foregroundStyle(.primary)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel(name.capitalized + (accentTheme == name ? ", selected" : ""))
                }
            }.padding(.vertical, 6)
            Toggle("Compact habits and tasks", isOn: $compactRows)
            Text("Fits more items by reducing spacing. Larger accessibility text keeps the room it needs.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct RemindersSection: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Binding var message: String?
    var body: some View {
        Section {
            Button(action: allow) { Label { Text("Allow Notifications") } icon: { Image(systemName: "bell").foregroundStyle(accent.fill) } }
        } header: { Text("Reminders") } footer: {
            Text("Set reminders on individual tasks and habits. Orbit only sends the reminders you choose.")
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
    @AppStorage("calendarFirstWeekday") private var firstWeekday = Calendar.current.firstWeekday
    @Binding var message: String?
    var body: some View {
        Section {
            Picker("Start week on", selection: $firstWeekday) { Text("Sunday").tag(1); Text("Monday").tag(2) }
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

private struct ProgressSection: View {
    @AppStorage("progressIncludesTasks") private var includeTasks = true
    @AppStorage("showOverallProgress") private var showOverall = false
    @AppStorage("overallProgressRange") private var range = 30
    @AppStorage("consistencyRange") private var widgetRange = 7
    var body: some View {
        Section("Today & Progress") {
            Toggle("Include tasks in daily progress", isOn: $includeTasks)
            Toggle("Show overall progress", isOn: $showOverall)
            Picker("Overall progress", selection: $range) { Text("Past week").tag(7); Text("Past month").tag(30) }
            Picker("Widget history", selection: $widgetRange) { Text("Past week").tag(7); Text("Past month").tag(30) }
            Text("Recent progress shows the last seven days. To correct a habit check-in, open Habits → History.").font(.footnote).foregroundStyle(.secondary)
        }
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
