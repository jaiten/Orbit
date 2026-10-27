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
    @State private var captureDockHeight: CGFloat = 0
    @State private var errorMessage: String?
    @AppStorage("onboarded") private var onboarded = false
    @State private var showOnboarding = false
    @State private var openAccountAfterOnboarding = false
    @State private var showAccount = false
    @State private var confirmShakeUndo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TabView(selection: $selectedTab) {
            // Line icons, as on the website; the selected tab takes the accent.
            TodayView().tabItem { Label("Today", systemImage: "sun.max").environment(\.symbolVariants, .none) }.tag(0)
            CalendarView().tabItem { Label("Calendar", systemImage: "calendar").environment(\.symbolVariants, .none) }.tag(1)
            NotesView().tabItem { Label("Notes", systemImage: "note.text").environment(\.symbolVariants, .none) }.tag(2)
            HabitsView().tabItem { Label("Habits", systemImage: "repeat").environment(\.symbolVariants, .none) }.tag(3)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape").environment(\.symbolVariants, .none) }.tag(4)
        }
        .onPreferenceChange(CaptureDockHeight.self) { captureDockHeight = $0 }
        // Undo appears only for deletions, moves and imports. It springs up from the bottom and slides
        // away again; shaking the phone offers the same Undo.
        .overlay(alignment: .bottom) {
            ZStack {
                if let change = undo.change {
                    HStack(spacing: 14) {
                        Text(change.kind.rawValue).font(.subheadline)
                        Button("Undo", action: performUndo).font(.subheadline.weight(.semibold))
                            .foregroundStyle(OrbitAccent(name: accentTheme).text)
                        Button { undo.dismiss() } label: { Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                            .accessibilityLabel("Dismiss Undo")
                    }
                    .padding(.leading, 18).padding(.trailing, 14).padding(.vertical, 12)
                    .background(Color.orbitSurface, in: Capsule()).overlay(Capsule().strokeBorder(Color.orbitLine))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    .padding(.bottom, 100 + (selectedTab == 0 || selectedTab == 2 ? captureDockHeight : 0))
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                    .task(id: change.created) { try? await Task.sleep(for: .seconds(8)); if undo.change?.created == change.created { undo.dismiss() } }
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .orbit, value: undo.change?.created)
        }
        .onReceive(NotificationCenter.default.publisher(for: .orbitShake)) { _ in
            if undo.change != nil && UIAccessibility.isShakeToUndoEnabled { confirmShakeUndo = true }
        }
        .alert("Undo \(undo.change?.kind.verb ?? "change")?", isPresented: $confirmShakeUndo) {
            Button("Cancel", role: .cancel) {}
            Button("Undo", action: performUndo)
        }
        .tint(DayTheme.accentText(accentTheme))
        // The one source for the accent: every view reads it from the environment and updates at once.
        .environment(\.orbitAccent, OrbitAccent(name: accentTheme))
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
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { if openAccountAfterOnboarding { showAccount = true } }) {
            OnboardingView { needsReminders, openAccount in
                onboarded = true; openAccountAfterOnboarding = openAccount; showOnboarding = false
                if needsReminders { Task { if await NotificationScheduler.shared.requestIfUndecided() { await refreshNotifications() } } }
            }.environment(\.orbitAccent, OrbitAccent(name: accentTheme))
        }
        .sheet(isPresented: $showAccount) {
            NavigationStack { AccountView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAccount = false } } } }
        }
        .task { decideOnboarding() }
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
        .onReceive(TimeChanges.publisher) { _ in
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
    /// First launch only. People who already have plans skip it; UI tests skip it unless they pass --onboarding.
    private func decideOnboarding() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") { showOnboarding = arguments.contains("--onboarding"); return }
        guard !onboarded else { return }
        let tasks = (try? context.fetchCount(FetchDescriptor<PlannerTask>())) ?? 0
        let habits = (try? context.fetchCount(FetchDescriptor<Habit>())) ?? 0
        if tasks + habits > 0 { onboarded = true } else { showOnboarding = true }
    }
    private func performUndo() {
        do { try undo.undo(in: context); Task { try? await refreshReminders(context) } } catch { errorMessage = error.localizedDescription }
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

extension Notification.Name {
    /// The device was shaken (see UIWindow.motionEnded below); RootView offers Undo.
    static let orbitShake = Notification.Name("OrbitShake")
}

extension UIWindow {
    /// Shake to undo, as in other iOS apps. Only posts a notification; RootView decides what to offer.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .orbitShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

@MainActor func refreshReminders(_ context: ModelContext) async throws {
    try await NotificationScheduler.shared.replace(with: NotificationScheduler.reminders(context: context))
}
