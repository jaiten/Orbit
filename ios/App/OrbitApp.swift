import SwiftUI
import SwiftData
import WidgetKit
import UIKit
import Combine

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
    @AppStorage("consistencyRange") private var consistencyRange = 7
    @ObservedObject private var undo = UndoJournal.shared
    @ObservedObject private var sync = SyncService.shared
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
        .overlay(alignment: .bottom) {
            if let change = undo.change {
                HStack {
                    Text("Change saved").font(.subheadline)
                    Button("Undo") { do { try undo.undo(in: context); Task { try? await refreshReminders(context) } } catch { errorMessage = error.localizedDescription } }.font(.subheadline.weight(.semibold))
                    Button { undo.dismiss() } label: { Image(systemName: "xmark").font(.caption) }.accessibilityLabel("Dismiss Undo")
                }.padding(14).background(.regularMaterial, in: Capsule()).padding(.bottom, 100)
                    .task(id: change.created) { try? await Task.sleep(for: .seconds(8)); if undo.change?.created == change.created { undo.dismiss() } }
            }
        }
        .tint(DayTheme.accentColor(accentTheme))
        .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
        .onOpenURL { url in
            if let code = RecoveryFlow.code(from: url) {
                selectedTab = 4
                Task { do { try await sync.acceptRecovery(code: code, context: context) } catch { errorMessage = error.localizedDescription } }
            }
            else if let notice = AuthConfirmation.notice(for: url) { selectedTab = 4; errorMessage = notice }
            else { selectedTab = 0 }
        }
        .sheet(isPresented: $sync.recoveryReady) { NavigationStack { PasswordChangeView() } }
        .task { do { try Migrations.run(context) } catch { errorMessage = error.localizedDescription }; applyNativeAccent(); DayTheme.sharedDefaults?.set(consistencyRange, forKey: "consistencyRange"); DayTheme.sharedDefaults?.set(accentTheme, forKey: "accentTheme"); UsageSignals.recordVisit(); await refreshNotifications() }
        .onChange(of: consistencyRange) { _, range in DayTheme.sharedDefaults?.set(range, forKey: "consistencyRange"); WidgetCenter.shared.reloadAllTimelines() }
        .onChange(of: accentTheme) { _, theme in applyNativeAccent(); DayTheme.sharedDefaults?.set(theme, forKey: "accentTheme"); WidgetCenter.shared.reloadAllTimelines() }
        .task {
            while !Task.isCancelled {
                if phase == .active { await SyncService.shared.run(context) }
                try? await Task.sleep(for: .seconds(20))
            }
        }
        // Travel or midnight: all-day dates stay on their day, habit reminders follow local time,
        // and timed reminders keep their instant.
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).merge(with: NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))) { _ in
            do { try Migrations.run(context) } catch { errorMessage = error.localizedDescription }
            Task { await refreshNotifications() }
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
    private func applyNativeAccent() {
        let color = UIColor(DayTheme.accentColor(accentTheme))
        UIView.appearance().tintColor = color
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.tintColor = color }
        }
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
