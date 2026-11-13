import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// A gentle note when a habit check-in lands a streak on a milestone (7 days, 4 weeks…).
/// Windows: celebrateStreak in windows/ui/core.js. Rules: HabitRules.streak and milestone.
@MainActor final class Celebration: ObservableObject {
    static let shared = Celebration()
    /// `big` moments (a finished day, a new badge) bring confetti and a stronger haptic.
    struct Moment: Equatable { let id = UUID(); let title: String; let text: String; let color: String; var big = false }
    @Published private(set) var moment: Moment?
    /// Set once after the first thing is finished, to offer the evening check-in on Today.
    @Published var offerCheckIn = false

    private func show(_ moment: Moment) {
        self.moment = moment
        UIAccessibility.post(notification: .announcement, argument: "\(moment.title), \(moment.text)")
        if moment.big { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        Task { try? await Task.sleep(for: .seconds(moment.big ? 5 : 4)); if self.moment == moment { self.moment = nil } }
    }

    /// Call after something is checked off (not undone). Plays the tick, then celebrates a day where
    /// everything planned is done, or a newly earned badge. The first time ever, badges already earned
    /// are recorded quietly.
    func finished(context: ModelContext) {
        Sounds.play(.tick)
        let tasks = (try? context.fetch(FetchDescriptor<PlannerTask>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<HabitLog>())) ?? []
        let defaults = UserDefaults.standard
        let earned = Rewards.earned(Rewards.metrics(tasks: tasks, logs: logs))
        let firstTime = defaults.object(forKey: "earnedBadges") == nil
        let seen = Set(defaults.stringArray(forKey: "earnedBadges") ?? [])
        let fresh = firstTime ? [] : earned.filter { !seen.contains($0) }
        defaults.set(Array(seen.union(earned)).sorted(), forKey: "earnedBadges")

        let today = PlannerLogic.today, date = PlannerLogic.todayDate
        let dayTasks = tasks.filter { !$0.note && TodayRules.onDay(TodayRules.item($0), day: today, today: today) }
        let due = habits.filter { PlannerLogic.plannerDay($0.createdAt) <= today && PlannerLogic.isDue($0, logs: logs, at: date) }
        let total = dayTasks.count + due.count
        let done = dayTasks.filter { $0.completedAt != nil }.count + due.filter { PlannerLogic.checkedToday($0, logs: logs, at: date) }.count
        if total > 0, done == total, defaults.string(forKey: "dayCompleteShown") != today {
            defaults.set(today, forKey: "dayCompleteShown")
            Sounds.play(.day)
            show(Moment(title: "Day complete", text: "All \(total) done. Nice work.", color: "", big: true))
        } else if let id = fresh.last, let badge = RewardsData.badges.first(where: { $0.id == id }) {
            Sounds.play(.badge)
            show(Moment(title: "Badge: \(badge.title)", text: badge.unlocks.map { "\($0.capitalized) accent unlocked" } ?? badge.detail, color: "", big: true))
        }
        offerCheckInOnce()
    }

    /// After the first thing finished, offer the evening check-in once (never during UI tests).
    private func offerCheckInOnce() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "eveningOffered") == nil, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        defaults.set(true, forKey: "eveningOffered")
        guard defaults.object(forKey: "eveningCheckIn") == nil else { return }
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status != .denied { offerCheckIn = true }
        }
    }

    /// Call after logging `habit` for `date`, with every habit log (including the new check-in).
    func checkIn(_ habit: Habit, logs: [HabitLog], at date: Date = PlannerLogic.todayDate) {
        let counts = PlannerLogic.counts(habit, logs: logs), day = PlannerLogic.dayKey(date)
        let rule = habit.frequencyRule, target = habit.target
        guard HabitRules.checked(rule: rule, target: target, counts: counts, day: day),
              let text = HabitRules.milestone(rule: rule, streak: HabitRules.streak(rule: rule, target: target, counts: counts, day: day, weekStart: HabitRules.weekStart()))
        else { return }
        show(Moment(title: habit.title, text: text, color: habit.color))
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
                    Circle().fill(moment.color.isEmpty ? DayTheme.accent : DayTheme.color(moment.color)).frame(width: 12, height: 12)
                        .overlay { if !reduceMotion { CompletionBurst(color: moment.color.isEmpty ? DayTheme.accent : DayTheme.color(moment.color), size: 12, duration: 0.8).id(moment.id) } }
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

/// Confetti for big moments, in the accent and habit colours. Off with Reduce Motion.
struct ConfettiOverlay: View {
    @ObservedObject private var celebration = Celebration.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if let moment = celebration.moment, moment.big, !reduceMotion {
            ConfettiBurst(seed: moment.id).allowsHitTesting(false).ignoresSafeArea().id(moment.id)
        }
    }
}

private struct ConfettiBurst: View {
    let seed: UUID
    @State private var start = Date.now
    private let colors: [Color] = [DayTheme.accent, DayTheme.color("sage"), DayTheme.color("lavender"), DayTheme.color("honey"), DayTheme.color("clay")]
    private let pieces: [(x: Double, vx: Double, vy: Double, size: Double, spin: Double, color: Int)] = (0..<80).map { _ in
        (Double.random(in: -0.15...0.15), Double.random(in: -260...260), Double.random(in: -620 ... -300), Double.random(in: 5...9), Double.random(in: -8...8), Int.random(in: 0..<5))
    }
    var body: some View {
        TimelineView(.animation) { timeline in
            let age = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard age < 1.8 else { return }
                for piece in pieces {
                    let x = size.width * (0.5 + piece.x) + piece.vx * age
                    let y = size.height * 0.6 + piece.vy * age + 700 * age * age
                    var copy = context
                    copy.opacity = max(0, 1 - age / 1.8)
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(piece.spin * age))
                    copy.fill(Path(CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)), with: .color(colors[piece.color]))
                }
            }
        }
    }
}

/// Shown once on Today after the first thing finished: an evening check-in, only if something is left.
struct EveningCheckInOffer: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @ObservedObject private var celebration = Celebration.shared
    var body: some View {
        if celebration.offerCheckIn {
            VStack(alignment: .leading, spacing: 8) {
                Text("Want a gentle evening check-in?").font(.subheadline.weight(.semibold))
                Text("At 8 PM, only on days something is still left.").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Turn on") {
                        celebration.offerCheckIn = false
                        Task {
                            guard (try? await NotificationScheduler.shared.requestPermission()) == true else { return }
                            UserDefaults.standard.set(20 * 60, forKey: "eveningCheckIn")
                            try? await refreshReminders(context)
                        }
                    }.buttonStyle(.borderedProminent).tint(accent.fill)
                    Button("Not now") { celebration.offerCheckIn = false }.buttonStyle(.bordered)
                }.font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .orbitCard()
            .transition(.opacity)
        }
    }
}
