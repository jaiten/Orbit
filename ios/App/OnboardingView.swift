import SwiftUI
import SwiftData

/// First launch: add a task, choose habits, optionally connect another device.
struct OnboardingView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    /// Called once at the end. `needsReminders`: a timed item or a habit was added, so it is a good moment to ask.
    var finish: (_ needsReminders: Bool, _ openAccount: Bool) -> Void
    @State private var step = 0
    @State private var text = ""
    @State private var chosen: Set<Int> = []
    @State private var needsReminders = false
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private var suggestions: [OnboardingData.HabitSuggestion] { OnboardingData.habitSuggestions.filter { $0.title != "Plan tomorrow" } }

    private var result: QuickAddResult { QuickAdd.parse(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch step {
                        case 0: capture
                        case 1: habits
                        default: sync
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in Circle().fill(index == step ? accent.fill : Color.secondary.opacity(0.3)).frame(width: 6, height: 6) }
                }.frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            .padding(24).tint(accent.fill)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(step == 2 ? "Start using Orbit" : "Skip") { next() }.accessibilityIdentifier("onboarding-skip")
                }
            }
            .modifier(MutationErrorModifier(error: $error))
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Orbit").font(.largeTitle.bold()).tracking(-1)
            Text("Keep your habits and daily tasks in one place. Add your first task below, or skip to start with an empty planner.").foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.body.weight(.medium)).foregroundStyle(.secondary)
                TextField("Call dentist tomorrow 9am", text: $text)
                    .font(.title3).focused($focused).submitLabel(.done).onSubmit(add).accessibilityIdentifier("onboarding-input")
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(.horizontal, 14).frame(minHeight: 52).orbitSurface()
            PreviewChip(text: result.title.isEmpty ? "" : QuickAdd.describe(result), identifier: "onboarding-preview").frame(minHeight: 34, alignment: .leading)
            Button("Add task and continue", action: add).buttonStyle(.borderedProminent).disabled(result.title.isEmpty)
            Button("Try example tasks") { save { try Examples.add(in: context); needsReminders = true } }
        }.onAppear { focused = true }
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your first habits").font(.largeTitle.bold()).tracking(-1)
            Text("Choose routines you want to repeat. Check them off as you go. You can change their schedules and reminders later.").foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    let on = chosen.contains(index)
                    Button { if !chosen.insert(index).inserted { chosen.remove(index) } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Text(detail(suggestion)).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(on ? accent.fill.opacity(0.14) : Color.orbitSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? accent.fill : Color.orbitLine, lineWidth: on ? 1.5 : 1))
                            .animation(.orbit, value: on)
                    }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Button("Continue") {
                save {
                    var picked: [String] = []
                    for index in chosen.sorted() {
                        let suggestion = suggestions[index]
                        // Each new habit gets the next colour, counting the ones picked just before it.
                        let color = try QuickAddSaver.nextHabitColor(in: context, adding: picked); picked.append(color)
                        let habit = Habit(title: suggestion.title, frequencyRule: suggestion.frequencyRule, target: suggestion.target, color: color)
                        habit.reminderMinutes = suggestion.reminderMinutes
                        context.insert(habit)
                    }
                    if !chosen.isEmpty { try Mutations.save(context); needsReminders = true }
                }
            }.buttonStyle(.borderedProminent)
        }
    }

    private var sync: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Use Orbit on your devices").font(.largeTitle.bold()).tracking(-1)
            Text("Sign in to share your tasks and habits between iPhone and Windows. This is optional: you can use Orbit on this iPhone without an account.").foregroundStyle(.secondary)
            Button("Sign in for sync") { finish(needsReminders, true) }.buttonStyle(.borderedProminent)
        }
    }

    private func detail(_ suggestion: OnboardingData.HabitSuggestion) -> String {
        if suggestion.frequencyRule == "WEEKLY" { return "\(suggestion.target) times a week" }
        return suggestion.target > 1 ? "\(suggestion.target) times a day" : HabitRules.label(suggestion.frequencyRule)
    }
    private func add() {
        let result = self.result
        guard !result.title.isEmpty else { return next() }
        save { try QuickAddSaver.save(result, in: context); if result.kind == .habit || result.time != nil { needsReminders = true } }
    }
    private func save(_ change: () throws -> Void) {
        do { try change(); next() } catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func next() {
        if step < 2 { withAnimation { step += 1 } } else { finish(needsReminders, false) }
    }
}
