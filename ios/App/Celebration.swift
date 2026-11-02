import SwiftUI
import UIKit

/// A gentle note when a habit check-in lands a streak on a milestone (7 days, 4 weeks…).
/// Windows: celebrateStreak in windows/ui/core.js. Rules: HabitRules.streak and milestone.
@MainActor final class Celebration: ObservableObject {
    static let shared = Celebration()
    struct Moment: Equatable { let id = UUID(); let title: String; let text: String; let color: String }
    @Published private(set) var moment: Moment?

    /// Call after logging `habit` for `date`, with every habit log (including the new check-in).
    func checkIn(_ habit: Habit, logs: [HabitLog], at date: Date = .now) {
        let counts = PlannerLogic.counts(habit, logs: logs), day = PlannerLogic.dayKey(date)
        let rule = habit.frequencyRule, target = habit.target
        guard HabitRules.checked(rule: rule, target: target, counts: counts, day: day),
              let text = HabitRules.milestone(rule: rule, streak: HabitRules.streak(rule: rule, target: target, counts: counts, day: day, weekStart: HabitRules.weekStart()))
        else { return }
        let moment = Moment(title: habit.title, text: text, color: habit.color)
        self.moment = moment
        UIAccessibility.post(notification: .announcement, argument: "\(habit.title), \(text)")
        Task { try? await Task.sleep(for: .seconds(4)); if self.moment == moment { self.moment = nil } }
    }
}

/// Shown at the top of the app for a few seconds, with the completion burst in the habit's colour.
struct CelebrationToast: View {
    @ObservedObject private var celebration = Celebration.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            if let moment = celebration.moment {
                HStack(spacing: 10) {
                    Circle().fill(DayTheme.color(moment.color)).frame(width: 12, height: 12)
                        .overlay { if !reduceMotion { CompletionBurst(color: DayTheme.color(moment.color), size: 12, duration: 0.8).id(moment.id) } }
                    Text(moment.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(moment.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.orbitSurface, in: Capsule()).overlay(Capsule().strokeBorder(Color.orbitLine))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                .accessibilityElement(children: .combine)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .orbit, value: celebration.moment)
    }
}
