import SwiftUI
import SwiftData

/// First launch: three short, skippable screens (capture, habits, sync). Content comes from
/// shared/onboarding.json, the same as Windows. Closing at any point finishes onboarding for good.
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

    private var result: QuickAddResult { QuickAdd.parse(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case 0: capture
                case 1: habits
                default: sync
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in Circle().fill(index == step ? accent.fill : Color.secondary.opacity(0.3)).frame(width: 6, height: 6) }
                }.frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            .padding(24).tint(accent.fill)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(step == 2 ? "Not Now" : "Skip") { next() }.accessibilityIdentifier("onboarding-skip")
                }
            }
            .modifier(MutationErrorModifier(error: $error))
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Orbit").font(.largeTitle.bold()).tracking(-1)
            Text("Type anything. Orbit works out when.").foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.body.weight(.medium)).foregroundStyle(.secondary)
                TextField("gym tomorrow 6pm", text: $text)
                    .font(.title3).focused($focused).submitLabel(.done).onSubmit(add).accessibilityIdentifier("onboarding-input")
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(.horizontal, 14).frame(minHeight: 52).orbitSurface()
            PreviewChip(text: result.title.isEmpty ? "" : QuickAdd.describe(result), identifier: "onboarding-preview").frame(minHeight: 34, alignment: .leading)
            Button("Add", action: add).buttonStyle(.borderedProminent).disabled(result.title.isEmpty)
            Button("Start with Examples") { save { try Examples.add(in: context); needsReminders = true } }
        }.onAppear { focused = true }
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick a habit or two").font(.largeTitle.bold()).tracking(-1)
            Text("Habits repeat on their own and reset at midnight.").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(OnboardingData.habitSuggestions.enumerated()), id: \.offset) { index, suggestion in
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
                    for index in chosen.sorted() {
                        let suggestion = OnboardingData.habitSuggestions[index]
                        let habit = Habit(title: suggestion.title, frequencyRule: suggestion.frequencyRule, target: suggestion.target)
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
            Text("Stay in sync").font(.largeTitle.bold()).tracking(-1)
            Text("Sign in to keep your iPhone and PC in step. Everything stays on this iPhone until you do.").foregroundStyle(.secondary)
            Button("Set Up Sync") { finish(needsReminders, true) }.buttonStyle(.borderedProminent)
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
