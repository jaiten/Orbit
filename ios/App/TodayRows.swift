import SwiftUI
import SwiftData

struct TodayItem: Identifiable {
    var task: PlannerTask? = nil
    var habit: Habit? = nil
    /// A small caption above the row ("This week"), where Today's habits move from daily to weekly or monthly.
    var caption: String? = nil
    var id: String { task.map { "task-" + $0.id.uuidString } ?? "habit-" + habit!.id.uuidString }
}

/// Rows inside a grouped list (one card with hairline dividers) draw no card of their own.
private struct GroupedRowsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var groupedRows: Bool {
        get { self[GroupedRowsKey.self] }
        set { self[GroupedRowsKey.self] = newValue }
    }
}

/// Tasks and habits in one card with hairline dividers inset past the tick, as in iOS Settings.
struct GroupedRows<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .environment(\.groupedRows, true)
            .orbitSurface(radius: CGFloat(DesignTokens.radiusRow))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(DesignTokens.radiusRow), style: .continuous))
    }
}

/// The soft shadow under a row that stands alone, and its outline with Increase Contrast. A grouped
/// row leaves both to its list.
private struct RowChrome: ViewModifier {
    let enabled: Bool
    let shape: RoundedRectangle
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            // Shadow from the shape's path (cheap while scrolling), not from the row's content.
            content.background { shape.fill(Color.orbitSurface).shadow(color: .black.opacity(0.03), radius: 2, y: 1) }
                .overlay { if contrast == .increased { shape.strokeBorder(Color.orbitLine, lineWidth: 1) } }
        } else { content }
    }
}

/// A choice under a row (such as starting a timer). With `options` it is a menu.
struct TileMove { let title: String; let action: () -> Void; var options: [TileMove] = [] }

/// Tasks and habits share the same controls: the check logs progress; the title opens details.
/// Swipe left for Delete (all the way deletes), right for Edit; touch and hold for everything else.
struct CheckTile: View {
    let title: String
    let subtitle: String
    let done: Bool
    let color: Color
    let completionLabel: String
    var toggle: () -> Void
    var edit: () -> Void
    var remove: () -> Void
    var moves: [TileMove] = []
    /// The detail is a habit count that has met its target (shown in the accent text colour).
    var met = false
    var icon: String? = nil
    var progress = 0 // 0: ordinary, 1: ready, 2: in progress
    var progressOptions: [TileMove] = []
    var allowsToggle = true
    /// On Today a tap on the title checks the item off too; editing is a swipe right or in the touch-and-hold menu.
    var tapChecks = false
    @Environment(\.orbitAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.groupedRows) private var grouped
    @AppStorage("compactRows") private var compactRows = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var rowHeight: CGFloat { compactRows && !typeSize.isAccessibilitySize ? 44 : (grouped ? 50 : 56) }
    /// A finger is down on the title; the whole row shows it, as rows do in iOS lists.
    @State private var pressed = false
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: grouped ? 0 : DayTheme.rowRadius, style: .continuous) }
    /// Standalone rows carry a faint tint of their colour; grouped rows only tint while in progress.
    private var tint: Double { progress == 2 ? 0.16 : grouped ? 0 : done ? 0.04 : 0.07 }

    var body: some View {
        SwipeRow(radius: grouped ? 0 : DayTheme.rowRadius, edit: edit, remove: remove) { swipe in
            row(swipe)
                .background { RowHighlight(pressed: pressed) }
                .background(color.opacity(tint))
                // Opaque even inside a grouped card, so a row slides and lifts as one solid piece.
                .background(Color.orbitSurface)
        }
        .overlay(shape.strokeBorder(color.opacity(progress == 2 && !grouped ? 0.4 : 0), lineWidth: 1))
        .modifier(RowChrome(enabled: !grouped, shape: shape))
        // Touch and hold lifts the row as a card of its own, with the text exactly where it was.
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous))
        .animation(reduceMotion ? nil : .orbit, value: progress)
    }

    private func row(_ swipe: SwipeRowState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button { if !swipe.takesTap() { toggle() } } label: {
                    ZStack {
                        if progress == 0 { OrbitTick(done: done, color: color) }
                        else {
                            Circle().fill(color.opacity(progress == 2 ? 0.16 : 0.06))
                            Circle().strokeBorder(color.opacity(0.22), lineWidth: 2)
                            Circle().trim(from: 0, to: progress == 2 ? 0.65 : 0)
                                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                            Image(systemName: progress == 2 ? "checkmark" : "play.fill")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(color)
                        }
                    }.frame(width: CGFloat(DesignTokens.rowTickLarge), height: CGFloat(DesignTokens.rowTickLarge))
                        .frame(width: 46, height: rowHeight).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!allowsToggle).accessibilityLabel(completionLabel)
                    .accessibilityValue(progress == 2 ? "In progress" : "")
                Button {
                    if swipe.takesTap() { return }
                    if tapChecks { if allowsToggle { toggle() } } else { edit() }
                } label: {
                    HStack(spacing: 8) {
                        if let icon { Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color).frame(width: 20).accessibilityHidden(true) }
                        line
                    }.padding(.leading, -2)
                }
                    .buttonStyle(RowPress(pressed: $pressed)).accessibilityLabel(tapChecks ? title : "Edit " + title)
                    .accessibilityHint(tapChecks ? "Checks it off. Swipe right or touch and hold to edit." : "")
                    .accessibilityValue(subtitle).accessibilityIdentifier("checklist-title")
                if !progressOptions.isEmpty {
                    Menu {
                        ForEach(progressOptions, id: \.title) { option in Button(option.title, action: option.action) }
                    } label: {
                        Image(systemName: progress == 0 ? "sparkles" : "ellipsis")
                            .font(.system(size: 16, weight: .medium)).frame(width: 44, height: rowHeight)
                    }.foregroundStyle(accent.text).accessibilityLabel("Progress options for " + title)
                }
            }
            if !moves.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { moveButtons }
                    VStack(alignment: .leading, spacing: 4) { moveButtons }
                }.padding(.leading, 46).padding(.bottom, 6)
            }
        }
    }

    private var moveButtons: some View {
        ForEach(moves, id: \.title) { move in
            Group {
                if move.options.isEmpty {
                    Button(move.title) { move.action() }
                } else {
                    Menu {
                        ForEach(Array(move.options.enumerated()), id: \.offset) { _, option in Button(option.title, action: option.action) }
                    } label: {
                        HStack(spacing: 4) { Text(move.title); Image(systemName: "chevron.down").font(.caption2.weight(.semibold)) }
                    }.accessibilityLabel("\(move.title): \(title)")
                }
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(accent.text)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(accent.fill.opacity(DesignTokens.tintAccentFill), in: Capsule())
            .frame(minHeight: 44)
            .buttonStyle(OrbitPress())
        }
    }

    /// Rows look the same everywhere: the title (up to two lines) and its detail. Notes, steps and other
    /// details appear only when the task is opened.
    private var line: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 7) { titleText; detailText }
            } else {
                HStack(spacing: 12) { titleText; Spacer(minLength: 8); detailText }
            }
        }.padding(.trailing, 14).padding(.vertical, typeSize.isAccessibilitySize ? 10 : 4)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading).contentShape(Rectangle())
    }
    private var titleText: some View {
        Text(title).font(.body).foregroundStyle(done ? .secondary : .primary)
            .strikethrough(done, color: .secondary)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal: false, vertical: true)
            .animation(reduceMotion ? nil : .orbit, value: done)
    }
    @ViewBuilder private var detailText: some View {
        if !subtitle.isEmpty {
            Text(subtitle).font(.footnote).monospacedDigit().foregroundStyle(met ? accent.text : .secondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        }
    }
}

struct TaskRow: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: PlannerTask
    var completionDate: Date = .now
    var tapChecks = false
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    @State private var startedFeedback = 0
    /// Set when this row was just started, to suggest a timer once.
    @State private var suggestTimer = false
    /// The tick as it shows while a tap waits to be saved (CompletionHold); nil follows the task.
    @State private var pending: Bool?
    @ObservedObject private var focus = FocusSession.shared
    private var timing: Bool { focus.taskID == task.id }
    private var done: Bool { pending ?? (task.completedAt != nil) }
    private var holdKey: String { "task-" + task.id.uuidString }
    private var moves: [TileMove] {
        if progress == 2 && suggestTimer && !timing {
            return [TileMove(title: "Start a timer", action: {}, options: FocusSession.options(for: task).map { minutes in
                        TileMove(title: FocusSession.label(minutes)) { startTimer(minutes) }
                    }),
                    TileMove(title: "Not now") { suggestTimer = false }]
        }
        return []
    }
    /// 1: ready to start, 2: in progress. A tick that is waiting to be saved shows as an ordinary tick.
    private var progress: Int {
        guard pending == nil else { return 0 }
        return PlannerLogic.plannerDay(completionDate) == PlannerLogic.today && task.completedAt == nil && task.progressTracking == true ? (task.startedAt == nil ? 1 : 2) : 0
    }
    private var progressOptions: [TileMove] {
        guard task.completedAt == nil, pending == nil else { return [] }
        if task.progressTracking == true {
            var options: [TileMove] = []
            if task.startedAt != nil && !timing {
                options += FocusSession.options(for: task).map { minutes in TileMove(title: "Start \(FocusSession.label(minutes)) timer") { startTimer(minutes) } }
            }
            if timing { options.append(TileMove(title: "Stop timer") { Task { await focus.stop() } }) }
            if task.startedAt != nil { options.append(TileMove(title: "Reset progress") { change { try Mutations.setProgress(task, enabled: true, in: context) } }) }
            options.append(TileMove(title: "Turn off start & finish") { change { try Mutations.setProgress(task, enabled: false, in: context) } })
            return options
        }
        guard task.progressTracking == nil,
              TaskProgress.suggests(task.title) || TaskProgress.learned(for: task.title, excluding: task.id, in: context) == .suggest else { return [] }
        return [TileMove(title: "Track start & finish") { change { try Mutations.setProgress(task, enabled: true, in: context) } },
                TileMove(title: "No thanks") { change { try Mutations.setProgress(task, enabled: false, in: context) } }]
    }
    private var completionLabel: String { (done ? "Reopen " : progress == 1 ? "Start " : progress == 2 ? "Finish " : "Complete ") + task.title }
    private var subtitle: String {
        // Progress shows in the ring and row tint, so the title keeps the room (no "In progress" text).
        var parts: [String] = []
        if task.hasTime, let date = task.dueDate { parts.append(date.formatted(date: .omitted, time: .shortened)) }
        if !task.subtasks.isEmpty { parts.append("\(task.subtasks.filter(\.completed).count)/\(task.subtasks.count) steps") }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        CheckTile(title: task.title, subtitle: subtitle, done: done, color: accent.fill,
                  completionLabel: completionLabel,
                  toggle: toggle, edit: edit, remove: remove, moves: moves, icon: ItemIcons.suggested(for: task.title), progress: progress, progressOptions: progressOptions, tapChecks: tapChecks)
            .modifier(TaskActions(task: task, edit: edit)).modifier(MutationErrorModifier(error: $error))
            .sensoryFeedback(.impact(weight: .light), trigger: feedback)
            .sensoryFeedback(.impact(weight: .medium), trigger: startedFeedback)
    }
    /// The tick answers at once; the task itself is saved after a short pause (CompletionHold), when
    /// the row folds away. Tapping again inside the pause simply takes the tick back.
    private func toggle() {
        if progress == 1 {
            change { try Mutations.setProgress(task, enabled: true, start: true, in: context); startedFeedback += 1; suggestTimer = true }
            return
        }
        let saved = task.completedAt != nil, target = !done
        feedback += 1
        if target { Sounds.play(.tick) }
        if target == saved { pending = nil; CompletionHold.shared.cancel(holdKey); return }
        pending = target
        CompletionHold.shared.schedule(holdKey) { commit(target) }
    }
    private func commit(_ target: Bool) {
        pending = nil
        guard task.modelContext != nil, !task.isDeleted, (task.completedAt != nil) != target else { return }
        do {
            try Mutations.toggle(task, at: completionDate, in: context)
            if task.completedAt != nil {
                let id = task.id
                Task { await FocusSession.shared.stopIfMatching(id) }
                Celebration.shared.settled(context: context)
            }
            ReminderRefresh.soon(context)
        } catch { self.error = error.localizedDescription }
    }
    private func remove() {
        CompletionHold.shared.cancel(holdKey)
        withAnimation(reduceMotion ? nil : .orbitFold) { change { context.delete(task); try Mutations.save(context) } }
    }
    private func startTimer(_ minutes: Int) {
        suggestTimer = false
        Task { do { try await focus.start(task, minutes: minutes) } catch { self.error = error.localizedDescription } }
    }
    private func change(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { self.error = error.localizedDescription }
    }
}

struct HabitRow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let habit: Habit
    /// This habit's check-ins by day (PlannerLogic.countsByHabit), worked out once by the list.
    let counts: [String: Int]
    let date: Date
    var tapChecks = false
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    /// The tick as it shows while a tap waits to be saved (CompletionHold); nil follows the check-ins.
    @State private var pending: Bool?
    private var saved: Bool { PlannerLogic.checkedToday(habit, counts: counts, at: date) }
    private var checked: Bool { pending ?? saved }
    private var canLog: Bool { PlannerLogic.dayKey(date) == PlannerLogic.today }
    private var holdKey: String { "habit-" + habit.id.uuidString }
    var body: some View {
        CheckTile(title: habit.title, subtitle: PlannerLogic.detail(habit, counts: counts, at: date), done: checked, color: DayTheme.color(habit.color),
                  completionLabel: (checked ? "Undo " : "Log ") + habit.title,
                  toggle: toggle, edit: edit, remove: remove, met: checked, icon: ItemIcons.symbol(habit.icon, title: habit.title), allowsToggle: canLog, tapChecks: tapChecks)
            .modifier(HabitActions(habit: habit, edit: edit))
            .modifier(MutationErrorModifier(error: $error))
            .sensoryFeedback(.impact(weight: .light), trigger: feedback)
    }
    private func toggle() {
        guard canLog else { return }
        feedback += 1
        // One of several check-ins today that does not yet meet the target: count it straight away.
        if !saved && pending == nil && (counts[PlannerLogic.dayKey(date)] ?? 0) + 1 < PlannerLogic.dailyTarget(habit) {
            Sounds.play(.tick)
            change { try Mutations.log(habit, at: date, in: context) }
            return
        }
        let target = !checked
        if target { Sounds.play(.tick) }
        if target == saved { pending = nil; CompletionHold.shared.cancel(holdKey); return }
        pending = target
        CompletionHold.shared.schedule(holdKey) { commit(target) }
    }
    private func commit(_ target: Bool) {
        pending = nil
        guard habit.modelContext != nil, !habit.isDeleted else { return }
        do {
            if target {
                try Mutations.log(habit, at: date, in: context)
                Celebration.shared.settled(context: context, habit: habit, at: date)
            } else {
                try Mutations.undoLog(habit, at: date, in: context)
            }
            ReminderRefresh.soon(context)
        } catch { self.error = error.localizedDescription }
    }
    private func remove() {
        CompletionHold.shared.cancel(holdKey)
        withAnimation(reduceMotion ? nil : .orbitFold) { change { try Conversions.remove(habit, in: context) } }
    }
    private func change(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { self.error = error.localizedDescription }
    }
}
