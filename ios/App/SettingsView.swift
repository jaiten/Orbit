import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearance = "system"
    @Query private var tasks: [PlannerTask]
    @Query private var habits: [Habit]
    @Query(sort: \IdeaPrompt.updatedAt) private var ideas: [IdeaPrompt]
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @AppStorage("generalCheckIn") private var checkIn = false
    @AppStorage("checkInMinutes") private var checkInMinutes = 1080
    @AppStorage("orbitVisitDays") private var visitDays = 0
    @State private var message: String?
    @ObservedObject private var calendars = CalendarBridge.shared
    @ObservedObject private var sync = SyncService.shared
    @Query private var syncEntries: [SyncEntry]
    @State private var email = ""
    @State private var password = ""
    @State private var signingIn = false
    @State private var confirmationCode = ""
    @State private var resendAfter = Date.distantPast
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) { OrbitMark(); VStack(alignment: .leading, spacing: 4) { Text("Orbit").font(.title.weight(.bold)); Text("\(visitDays) days showing up").font(.caption).foregroundStyle(.secondary) } }
                    Text("A little space for what matters.").foregroundStyle(.secondary)
                }
                Section("Across your devices") {
                    if let account = sync.email {
                        Text(account)
                        NavigationLink("Devices & active sign-ins") { DevicesView() }
                        Button("Sync now") { Task { await sync.run(context) } }
                        Button("Sign out") { Task { do { try await sync.signOut() } catch { message = error.localizedDescription } } }
                    } else {
                        TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(.password)
                        Button("Sign in") { authenticate(create: false) }.disabled(signingIn || email.isEmpty || password.isEmpty)
                        Button("Create account") { authenticate(create: true) }.disabled(signingIn || email.isEmpty || password.count < 8)
                        DisclosureGroup("Email confirmation") {
                            Text("Open the newest confirmation email and tap its link, then sign in above. If you have a confirmation code, you can enter it below.").font(.footnote).foregroundStyle(.secondary)
                            TextField("Confirmation code (if provided)", text: $confirmationCode)
                                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                            Button("Confirm account") { confirmAccount() }
                                .disabled(signingIn || email.isEmpty || confirmationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Button(timeline.date < resendAfter ? "Resend available shortly" : "Resend confirmation email") { resendCode() }
                                    .disabled(signingIn || email.isEmpty || timeline.date < resendAfter)
                            }
                            Text("Enter the newest code from your email. Expired links cannot be reused.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("Sign in on your PC with the same account. Your existing planner will be added to that account and stay available offline.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(syncEntries.filter { $0.conflict != nil }) { entry in
                    Section("Review two versions") {
                        Text("Both versions are saved. Choose the content you want to keep.").font(.footnote).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("On this iPhone").font(.caption).foregroundStyle(.secondary)
                            Text(SyncMerge.summary((try? SyncRecords.object(entry.payload)) ?? [:], deleted: entry.tombstone))
                            Button("Use the version above") { resolve(entry, local: true) }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("From sync").font(.caption).foregroundStyle(.secondary)
                            let record = (try? SyncRecords.object(entry.conflict ?? "{}")) ?? [:]
                            Text(SyncMerge.summary(record["payload"] as? [String: Any] ?? [:], deleted: record["deleted"] as? Bool ?? false))
                            Button("Use this synced version") { resolve(entry, local: false) }
                        }
                    }
                }
                Section("Calendars") {
                    if calendars.connected {
                        Label("Calendars connected", systemImage: "checkmark.circle")
                        Button("Disconnect calendars") { calendars.disconnect() }
                    } else {
                        Button("Connect calendars", systemImage: "calendar") {
                            Task { do { try await calendars.connect() } catch { message = error.localizedDescription } }
                        }
                    }
                    Text("See events from Apple Calendar and Google accounts added to your iPhone. Touch and hold a to-do to send it to a calendar. Changes to calendar events do not change the original task.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Accent") {
                    HStack {
                        ForEach(DayTheme.accents, id: \.self) { name in
                            Button { accentTheme = name } label: {
                                VStack(spacing: 8) {
                                    Circle().fill(DayTheme.accentColor(name)).frame(width: 34, height: 34).overlay { if accentTheme == name { Image(systemName: "checkmark").foregroundStyle(.white) } }
                                    Text(name == "honey" ? "Honey" : name.capitalized).font(.caption2).foregroundStyle(.primary)
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).accessibilityLabel(name.capitalized + (accentTheme == name ? ", selected" : ""))
                        }
                    }.padding(.vertical, 6)
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
                Section("A moment for yourself") {
                    Toggle("Daily check-in", isOn: $checkIn)
                        .onChange(of: checkIn) { _, enabled in
                            Task { do { if enabled { _ = try await NotificationScheduler.shared.requestPermission() }; try await refreshReminders(context) } catch { message = error.localizedDescription } }
                        }
                    if checkIn {
                        DatePicker("At", selection: Binding(get: { Calendar.current.date(bySettingHour: checkInMinutes / 60, minute: checkInMinutes % 60, second: 0, of: .now)! }, set: { date in
                            checkInMinutes = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
                            Task { try? await refreshReminders(context) }
                        }), displayedComponents: .hourAndMinute)
                        Button("Use my usual check-in time") { checkInMinutes = UsageSignals.suggestedMinutes(); Task { try? await refreshReminders(context) } }
                    }
                    Text("One gentle reminder, independent of your to-dos. Time suggestions use only check-in counts stored on this device. After three visits at a similar time, Orbit can suggest that hour. You stay in control.").font(.footnote).foregroundStyle(.secondary)
                }
                if tasks.isEmpty && habits.isEmpty {
                    Section { Button("Explore with sample data", action: seed) }
                }
                Section("About this prototype") {
                    Text("Offline first. Sign in to share your planner with Orbit for Windows. Sync runs while the app is open; widget changes sync when you reopen Orbit.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { SyncIndicator() } }
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
    private func confirmAccount() {
        signingIn = true
        Task {
            defer { signingIn = false }
            do { try await sync.confirm(email: email, code: confirmationCode, context: context); confirmationCode = ""; password = "" }
            catch { message = error.localizedDescription }
        }
    }
    private func resendCode() {
        signingIn = true
        Task {
            defer { signingIn = false }
            do { try await sync.resendConfirmation(email: email); resendAfter = .now.addingTimeInterval(60); message = "If this account needs confirmation, a fresh confirmation email is on its way." }
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
