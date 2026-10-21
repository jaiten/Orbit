import SwiftUI
import SwiftData

struct TodayItem: Identifiable {
    var task: PlannerTask? = nil
    var habit: Habit? = nil
    var id: String { task.map { "task-" + $0.id.uuidString } ?? "habit-" + habit!.id.uuidString }
    /// Identity plus done state, so lists animate when an item finishes or moves.
    var state: String { id + (task?.completedAt == nil ? "" : "-done") }
}

struct TileMove { let title: String; let action: () -> Void }

/// A checklist row, as on the website: surface with a 1px line, 56pt tall. Tasks: the tick completes,
/// the rest of the row opens it. Habits: a colour dot and the count; tapping the row logs one check-in.
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
    /// Habit rows: a dot instead of a tick, and the whole row logs.
    var habit = false
    /// The detail is a habit count that has met its target (shown in the accent text colour).
    var met = false
    /// A trailing pencil, for habits on the Habits tab where tapping the row logs.
    var showEdit = false
    @Environment(\.orbitAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var homeDrag = HomeDrag.shared
    @State private var actionEdge = 0
    @State private var dragOffset: CGFloat = 0
    @State private var gestureMoved = false
    @GestureState private var gestureActive = false
    private var revealed: Bool { actionEdge == -1 || dragOffset < 0 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous) }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteButton
            row.orbitSurface()
                .offset(x: max(-76, min(0, CGFloat(actionEdge == -1 ? -70 : 0) + dragOffset)))
        }
        .background(revealed ? Color.red : Color.clear, in: shape).clipShape(shape)
        .contentShape(Rectangle())
        .modifier(SwipeToReveal(changed: swipeChanged, ended: swipeEnded, legacy: swipe))
        .onChange(of: gestureActive) { _, active in
            if !active { dragOffset = 0; Task { try? await Task.sleep(for: .milliseconds(150)); gestureMoved = false } }
        }
        .onChange(of: homeDrag.item) { _, value in if value != nil { actionEdge = 0; dragOffset = 0; gestureMoved = true } }
        .animation(reduceMotion ? nil : .orbit, value: actionEdge)
    }

    private var deleteButton: some View {
        Button { remove(); actionEdge = 0 } label: {
            Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 64, height: 56)
        }.buttonStyle(.plain).accessibilityLabel("Delete").accessibilityHidden(!revealed).opacity(revealed ? 1 : 0)
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 0) {
            if habit {
                HStack(spacing: 0) {
                    Button(action: tapMain) { line(leading: AnyView(dot)) }
                        .buttonStyle(OrbitPress()).accessibilityLabel(completionLabel).accessibilityValue(subtitle).accessibilityIdentifier("checklist-title")
                    if showEdit {
                        Button(action: tapEdit) {
                            Image(systemName: "pencil").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).frame(width: 44, height: 56).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Edit " + title)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    Button(action: tapMain) { OrbitTick(done: done, color: color).frame(width: 46, height: 56).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel(completionLabel)
                    Button(action: tapEdit) { line(leading: nil).padding(.leading, -2) }
                        .buttonStyle(OrbitPress()).accessibilityLabel("Edit " + title).accessibilityValue(subtitle).accessibilityIdentifier("checklist-title")
                }
            }
            if !moves.isEmpty {
                HStack(spacing: 8) {
                    ForEach(moves, id: \.title) { move in
                        Button(move.title) { move.action() }
                            .font(.subheadline.weight(.medium)).foregroundStyle(accent.text)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(accent.fill.opacity(DesignTokens.tintAccentFill), in: Capsule())
                            .buttonStyle(OrbitPress())
                    }
                }.padding(.leading, 50).padding(.bottom, 14).padding(.top, -4)
            }
        }
    }

    private func line(leading: AnyView?) -> some View {
        HStack(spacing: 12) {
            if let leading { leading }
            Text(title).font(.body).foregroundStyle(done && !habit ? .secondary : .primary)
                .strikethrough(done && !habit, color: .secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: done)
            Spacer(minLength: 8)
            if !subtitle.isEmpty {
                Text(subtitle).font(.footnote).monospacedDigit().foregroundStyle(met ? accent.text : .secondary).lineLimit(1)
            }
        }
        .padding(.leading, habit ? 14 : 0).padding(.trailing, habit && showEdit ? 0 : 14)
        .frame(minHeight: 56).contentShape(Rectangle())
    }

    private var dot: some View { HabitDot(done: done, color: color) }

    private func tapMain() { if !gestureMoved && homeDrag.item == nil { if actionEdge == 0 { toggle() } else { actionEdge = 0 } } }
    private func tapEdit() { if !gestureMoved && homeDrag.item == nil { if actionEdge == 0 { edit() } else { actionEdge = 0 } } }

    private func swipeChanged(_ x: CGFloat) {
        gestureMoved = true
        if homeDrag.item == nil { dragOffset = x }
    }
    private func swipeEnded(_ x: CGFloat) {
        if homeDrag.item == nil {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                actionEdge = CGFloat(actionEdge == -1 ? -70 : 0) + x < -32 ? -1 : 0
                dragOffset = 0
            }
        } else { dragOffset = 0 }
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
                if homeDrag.item == nil && abs(value.translation.width) > abs(value.translation.height) * 1.4 { dragOffset = value.translation.width }
            }
            .onEnded { value in
                guard homeDrag.item == nil && abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                    actionEdge = CGFloat(actionEdge == -1 ? -70 : 0) + value.translation.width < -32 ? -1 : 0
                    dragOffset = 0
                }
            }
    }
}

/// A habit's 10pt colour dot; it pops when the habit is checked.
private struct HabitDot: View {
    let done: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 1
    var body: some View {
        Circle().fill(color).frame(width: DesignTokens.rowDot, height: DesignTokens.rowDot).scaleEffect(pop)
            .onChange(of: done) { _, now in
                guard now, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.16)) { pop = 1.5 } completion: { withAnimation(.orbit) { pop = 1 } }
            }
            .accessibilityHidden(true)
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
    var dragEnabled = false
    /// Overdue tasks on Today offer Today / Later / Someday.
    var showMoves = false
    var edit: () -> Void
    @State private var error: String?
    @State private var feedback = 0
    private var overdue: Bool { showMoves && TodayRules.isOverdue(TodayRules.item(task), today: PlannerLogic.dayKey(.now)) }
    private var moves: [TileMove] {
        guard overdue else { return [] }
        return [TileMove(title: "Today") { change { TodayRules.moveToDay(task, day: .now); try Mutations.save(context) } },
                TileMove(title: "Later") { change { TodayRules.moveLater(task); try Mutations.save(context) } },
                TileMove(title: "Someday") { change { try TodayRules.moveToSomeday(task, in: context); try Mutations.save(context) } }]
    }
    private var subtitle: String {
        var parts: [String] = []
        if overdue, let day = task.day { parts.append(TodayRules.overdueLabel(day, today: PlannerLogic.dayKey(.now))) }
        if task.hasTime, let date = task.dueDate { parts.append(date.formatted(date: .omitted, time: .shortened)) }
        if !task.subtasks.isEmpty { parts.append("\(task.subtasks.filter(\.completed).count)/\(task.subtasks.count) steps") }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        CheckTile(title: task.title, subtitle: subtitle, done: task.completedAt != nil, color: accent.fill,
                  completionLabel: (task.completedAt == nil ? "Complete " : "Reopen ") + task.title,
                  toggle: toggle, edit: edit, remove: { change { context.delete(task); try Mutations.save(context) } }, moves: moves)
            .modifier(TaskActions(task: task, enabled: !dragEnabled)).modifier(MutationErrorModifier(error: $error)).sensoryFeedback(.success, trigger: feedback)
    }
    private func toggle() {
        change {
            try Mutations.toggle(task, in: context); feedback += 1
            if task.completedAt != nil { Task { await FocusSession.shared.stopIfMatching(task.id) } }
        }
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
    var edit: (() -> Void)? = nil
    /// Show a pencil (the Habits tab); on Today, habits are edited from there.
    var editable = false
    @State private var error: String?
    @State private var feedback = 0
    private var checked: Bool { PlannerLogic.checkedToday(habit, logs: logs, at: date) }
    var body: some View {
        CheckTile(title: habit.title, subtitle: PlannerLogic.detail(habit, logs: logs, at: date), done: checked, color: DayTheme.color(habit.color),
                  completionLabel: (checked ? "Undo " : "Log ") + habit.title,
                  toggle: toggle, edit: { edit?() }, remove: { change { try Conversions.remove(habit, in: context) } }, habit: true, met: checked, showEdit: editable)
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
