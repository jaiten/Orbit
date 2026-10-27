import SwiftUI
import SwiftData

struct TodayItem: Identifiable {
    var task: PlannerTask? = nil
    var habit: Habit? = nil
    var id: String { task.map { "task-" + $0.id.uuidString } ?? "habit-" + habit!.id.uuidString }
}

struct TileMove { let title: String; let action: () -> Void }

/// Tasks and habits share the same controls: the check logs progress; the title opens details.
/// Overdue tasks show Today / Later / Someday. A left swipe reveals Delete.
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
    @Environment(\.orbitAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("compactRows") private var compactRows = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var rowHeight: CGFloat { compactRows && !typeSize.isAccessibilitySize ? 44 : 56 }
    @State private var actionEdge = 0
    @State private var dragOffset: CGFloat = 0
    @State private var gestureMoved = false
    @GestureState private var gestureActive = false
    private var revealed: Bool { actionEdge == -1 || dragOffset < 0 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous) }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteButton
            row
                .background(color.opacity(progress == 2 ? 0.16 : done ? 0.04 : 0.07), in: shape)
                .orbitSurface()
                .overlay(shape.strokeBorder(color.opacity(progress == 2 ? 0.4 : 0), lineWidth: 1))
                .offset(x: max(-76, min(0, CGFloat(actionEdge == -1 ? -70 : 0) + dragOffset)))
        }
        .background(revealed ? Color.red : Color.clear, in: shape).clipShape(shape)
        .contentShape(Rectangle())
        .modifier(SwipeToReveal(changed: swipeChanged, ended: swipeEnded, legacy: swipe))
        .onChange(of: gestureActive) { _, active in
            if !active { dragOffset = 0; Task { try? await Task.sleep(for: .milliseconds(150)); gestureMoved = false } }
        }
        .animation(reduceMotion ? nil : .orbit, value: actionEdge)
        .animation(reduceMotion ? nil : .orbit, value: progress)
    }

    private var deleteButton: some View {
        Button { remove(); actionEdge = 0 } label: {
            Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 64, height: rowHeight)
        }.buttonStyle(.plain).accessibilityLabel("Delete").accessibilityHidden(!revealed).opacity(revealed ? 1 : 0)
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button(action: tapMain) {
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
                }.buttonStyle(.plain).accessibilityLabel(completionLabel)
                    .accessibilityValue(progress == 2 ? "In progress" : "")
                Button(action: tapEdit) {
                    HStack(spacing: 8) {
                        if let icon { Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color).frame(width: 20).accessibilityHidden(true) }
                        line
                    }.padding(.leading, -2)
                }
                    .buttonStyle(OrbitPress()).accessibilityLabel("Edit " + title)
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
                        Button(move.title) { move.action() }
                            .font(.subheadline.weight(.medium)).foregroundStyle(accent.text)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(accent.fill.opacity(DesignTokens.tintAccentFill), in: Capsule())
                            .frame(minHeight: 44)
                            .buttonStyle(OrbitPress())
                    }
    }

    private var line: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { titleText; detailText }
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
    }
    @ViewBuilder private var detailText: some View {
        if !subtitle.isEmpty {
            Text(subtitle).font(.footnote).monospacedDigit().foregroundStyle(met ? accent.text : .secondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        }
    }

    private func tapMain() { if !gestureMoved { if actionEdge == 0 { toggle() } else { actionEdge = 0 } } }
    private func tapEdit() { if !gestureMoved { if actionEdge == 0 { edit() } else { actionEdge = 0 } } }

    private func swipeChanged(_ x: CGFloat) {
        gestureMoved = true
        dragOffset = x
    }
    private func swipeEnded(_ x: CGFloat) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
            actionEdge = CGFloat(actionEdge == -1 ? -70 : 0) + x < -32 ? -1 : 0
            dragOffset = 0
        }
        Task { try? await Task.sleep(for: .milliseconds(150)); gestureMoved = false }
    }

    /// iOS 17 only; iOS 18 and later use `SidewaysPan`, which leaves vertical drags to the scroll view.
    private var swipe: some Gesture {
        // Starts later than the page's own scrolling (about 10 pt), so vertical movement scrolls
        // and only a clearly sideways swipe reveals Delete.
        DragGesture(minimumDistance: 24)
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                gestureMoved = true
                if abs(value.translation.width) > abs(value.translation.height) * 1.4 { dragOffset = value.translation.width }
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                    actionEdge = CGFloat(actionEdge == -1 ? -70 : 0) + value.translation.width < -32 ? -1 : 0
                    dragOffset = 0
                }
            }
    }
}

/// The left swipe that reveals Delete: a UIKit pan on iOS 18 and later, the SwiftUI gesture on iOS 17.
private struct SwipeToReveal<Legacy: Gesture>: ViewModifier {
    var changed: (CGFloat) -> Void
    var ended: (CGFloat) -> Void
    var legacy: Legacy
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.gesture(SidewaysPan(changed: changed, ended: ended)) }
        else { content.simultaneousGesture(legacy) }
    }
}

struct TaskRow: View {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.modelContext) private var context
    let task: PlannerTask
    /// Overdue tasks on Today offer Today / Later / Someday.
    var showMoves = false
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    @State private var startedFeedback = 0
    /// Set when this row was just started, to suggest a timer once.
    @State private var suggestTimer = false
    @ObservedObject private var focus = FocusSession.shared
    private var timing: Bool { focus.taskID == task.id }
    private var overdue: Bool { showMoves && TodayRules.isOverdue(TodayRules.item(task), today: PlannerLogic.dayKey(.now)) }
    private var timerMinutes: Int { min(240, max(5, task.durationMinutes)) }
    private var moves: [TileMove] {
        if progress == 2 && suggestTimer && !timing {
            return [TileMove(title: "Start a \(timerMinutes)-min timer") { startTimer() },
                    TileMove(title: "Not now") { suggestTimer = false }]
        }
        guard overdue else { return [] }
        return [TileMove(title: "Today") { change { TodayRules.moveToDay(task, day: .now); try Mutations.save(context) } },
                TileMove(title: "Later") { change { TodayRules.moveLater(task); try Mutations.save(context) } },
                TileMove(title: "Someday") { change { try TodayRules.moveToSomeday(task, in: context); try Mutations.save(context) } }]
    }
    private var progress: Int { task.completedAt == nil && task.progressTracking == true ? (task.startedAt == nil ? 1 : 2) : 0 }
    private var progressOptions: [TileMove] {
        guard task.completedAt == nil else { return [] }
        if task.progressTracking == true {
            var options: [TileMove] = []
            if task.startedAt != nil && !timing { options.append(TileMove(title: "Start timer") { startTimer() }) }
            if timing { options.append(TileMove(title: "Stop timer") { Task { await focus.stop() } }) }
            if task.startedAt != nil { options.append(TileMove(title: "Reset progress") { change { try Mutations.setProgress(task, enabled: true, in: context) } }) }
            options.append(TileMove(title: "Turn off start & finish") { change { try Mutations.setProgress(task, enabled: false, in: context) } })
            return options
        }
        guard task.progressTracking == nil && TaskProgress.suggests(task.title) else { return [] }
        return [TileMove(title: "Track start & finish") { change { try Mutations.setProgress(task, enabled: true, in: context) } },
                TileMove(title: "No thanks") { change { try Mutations.setProgress(task, enabled: false, in: context) } }]
    }
    private var completionLabel: String { (task.completedAt != nil ? "Reopen " : progress == 1 ? "Start " : progress == 2 ? "Finish " : "Complete ") + task.title }
    private var subtitle: String {
        var parts: [String] = []
        if task.completedAt == nil && task.progressTracking == true { parts.append(task.startedAt == nil ? "Ready to start" : timing ? "Timer running" : "In progress") }
        if overdue, let day = task.day { parts.append(TodayRules.overdueLabel(day, today: PlannerLogic.dayKey(.now))) }
        if task.hasTime, let date = task.dueDate { parts.append(date.formatted(date: .omitted, time: .shortened)) }
        if !task.subtasks.isEmpty { parts.append("\(task.subtasks.filter(\.completed).count)/\(task.subtasks.count) steps") }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        CheckTile(title: task.title, subtitle: subtitle, done: task.completedAt != nil, color: accent.fill,
                  completionLabel: completionLabel,
                  toggle: toggle, edit: edit, remove: { change { context.delete(task); try Mutations.save(context) } }, moves: moves, icon: ItemIcons.suggested(for: task.title), progress: progress, progressOptions: progressOptions)
            .modifier(TaskActions(task: task)).modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
            .sensoryFeedback(.impact(weight: .medium), trigger: startedFeedback)
    }
    private func toggle() {
        if progress == 1 {
            change { try Mutations.setProgress(task, enabled: true, start: true, in: context); startedFeedback += 1; suggestTimer = true }
            return
        }
        change {
            try Mutations.toggle(task, in: context); feedback += 1
            if task.completedAt != nil { Task { await FocusSession.shared.stopIfMatching(task.id) } }
        }
    }
    private func startTimer() {
        suggestTimer = false
        Task { do { try await focus.start(task) } catch { self.error = error.localizedDescription } }
    }
    private func change(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { self.error = error.localizedDescription }
    }
}

struct HabitRow: View {
    @Environment(\.modelContext) private var context
    let habit: Habit
    let logs: [HabitLog]
    let date: Date
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    private var checked: Bool { PlannerLogic.checkedToday(habit, logs: logs, at: date) }
    var body: some View {
        CheckTile(title: habit.title, subtitle: PlannerLogic.detail(habit, logs: logs, at: date), done: checked, color: DayTheme.color(habit.color),
                  completionLabel: (checked ? "Undo " : "Log ") + habit.title,
                  toggle: toggle, edit: edit, remove: { change { try Conversions.remove(habit, in: context) } }, met: checked, icon: ItemIcons.symbol(habit.icon, title: habit.title))
            .modifier(HabitActions(habit: habit))
            .modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
    }
    private func toggle() {
        change {
            if checked { try Mutations.undoLog(habit, at: date, in: context) } else { try Mutations.log(habit, at: date, in: context) }
            feedback += 1
        }
    }
    private func change(_ action: () throws -> Void) {
        do { try action(); Task { do { try await refreshReminders(context) } catch { self.error = error.localizedDescription } } }
        catch { self.error = error.localizedDescription }
    }
}
