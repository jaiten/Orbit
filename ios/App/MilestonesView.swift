import SwiftData
import SwiftUI

/// Every milestone badge, earned or with its progress, and the accent it unlocks (shared/rewards.json).
struct MilestonesView: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Query private var tasks: [PlannerTask]
    @Query private var logs: [HabitLog]
    var body: some View {
        let metrics = Rewards.metrics(tasks: tasks, logs: logs)
        let earned = Set(Rewards.earnedBadges(metrics))
        List {
            Section {
                Text("\(metrics.completions) things done on \(metrics.activeDays) \(metrics.activeDays == 1 ? "day" : "days"). Badges unlock new accent colours.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                ForEach(RewardsData.badges) { badge in
                    let done = earned.contains(badge.id)
                    let value = min(Rewards.value(metrics, badge.metric), badge.goal)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: done ? "star.fill" : "star").font(.title3).foregroundStyle(done ? accent.fill : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(badge.title).font(.body.weight(.semibold))
                            HStack(spacing: 6) {
                                Text(badge.detail)
                                if let unlock = badge.unlocks {
                                    Text("·")
                                    Circle().fill(DayTheme.accentColor(unlock)).frame(width: 9, height: 9)
                                    Text("Unlocks \(unlock)")
                                }
                            }.font(.footnote).foregroundStyle(.secondary)
                            if !done { ProgressView(value: Double(value), total: Double(badge.goal)).tint(accent.fill) }
                        }
                    }
                    .padding(.vertical, 4).opacity(done ? 1 : 0.8)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(done ? "Earned" : "\(value) of \(badge.goal)")
                }
            }
        }
        .scrollContentBackground(.hidden).background(DayTheme.canvas(scheme))
        .navigationTitle("Milestones").navigationBarTitleDisplayMode(.inline)
    }
}
