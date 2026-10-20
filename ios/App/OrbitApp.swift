import SwiftUI
import SwiftData

@main struct OrbitApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    init() {
        do {
            #if DEBUG
            container = try Persistence.makeContainer(inMemory: ProcessInfo.processInfo.arguments.contains("--ui-testing"))
            #else
            container = try Persistence.makeContainer()
            #endif
            startupError = nil
        }
        catch { container = nil; startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let container { RootView().modelContainer(container) }
            else {
                ContentUnavailableView("Your planner couldn’t open", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(startupError ?? "Please reopen Orbit."))
            }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("accentTheme") private var accentTheme = "coral"
    @State private var selectedTab = 0
    @State private var errorMessage: String?
    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView().tabItem { Label("Today", systemImage: "sun.max") }.tag(0)
            CalendarView().tabItem { Label("Calendar", systemImage: "calendar") }.tag(1)
            TasksView().tabItem { Label("Lists", systemImage: "checklist") }.tag(2)
            HabitsView().tabItem { Label("Habits", systemImage: "leaf") }.tag(3)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .tint(DayTheme.accentColor(accentTheme))
        .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
        .onOpenURL { url in
            if let notice = AuthConfirmation.notice(for: url) { selectedTab = 4; errorMessage = notice }
            else { selectedTab = 0 }
        }
        .task { UsageSignals.recordVisit(); await refreshNotifications() }
        .task {
            while !Task.isCancelled {
                if phase == .active { await SyncService.shared.run(context) }
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OrbitLocalChange"))) { _ in
            Task { await SyncService.shared.run(context) }
        }
        .onChange(of: phase) { _, value in
            if value == .active { UsageSignals.recordVisit(); SyncService.shared.resumeRealtime(); Task { await refreshNotifications(); await SyncService.shared.run(context) } }
            else { SyncService.shared.suspendRealtime() }
        }
        .alert("Orbit", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    private func refreshNotifications() async {
        do { try await NotificationScheduler.shared.replace(with: NotificationScheduler.reminders(context: context)) }
        catch { errorMessage = error.localizedDescription }
    }
}

/// All edits share persistence error reporting and reminder refresh.
struct MutationErrorModifier: ViewModifier {
    @Binding var error: String?
    func body(content: Content) -> some View {
        content.alert("Couldn’t finish that change", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

@MainActor func refreshReminders(_ context: ModelContext) async throws {
    try await NotificationScheduler.shared.replace(with: NotificationScheduler.reminders(context: context))
}
