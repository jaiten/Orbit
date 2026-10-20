import SwiftUI
import SwiftData

struct TodayItem: Identifiable {
    var task: PlannerTask? = nil
    var habit: Habit? = nil
    var id: String { task.map { "task-" + $0.id.uuidString } ?? "habit-" + habit!.id.uuidString }
    var short: Bool { let title = task?.title ?? habit!.title; return title.count <= 18 && title.split(separator: " ").allSatisfy { $0.count <= 10 } && task?.hasTime != true && (task?.subtasks.isEmpty ?? true) }
}

/// Pairs short tiles side by side when there is room.
struct TodayGroup: Identifiable {
    let items: [TodayItem]
    var id: String { items[0].id }
    static func groups(_ items: [TodayItem], compact: Bool) -> [TodayGroup] {
        var groups: [TodayGroup] = []; var index = 0
        while index < items.count {
            if compact, items[index].short, index + 1 < items.count, items[index + 1].short {
                groups.append(TodayGroup(items: [items[index], items[index + 1]])); index += 2
            } else { groups.append(TodayGroup(items: [items[index]])); index += 1 }
        }
        return groups
    }
}

struct TileMove { let title: String; let action: () -> Void }

/// A checklist row: the large area completes it, the pencil edits it, a left swipe reveals Delete.
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
            row.background(DayTheme.surface, in: shape)
                .offset(x: max(-76, min(0, CGFloat(actionEdge == -1 ? -70 : 0) + dragOffset)))
        }
        .background(revealed ? Color.red : Color.clear, in: shape).clipShape(shape)
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
        .onChange(of: gestureActive) { _, active in
            if !active { dragOffset = 0; Task { try? await Task.sleep(for: .milliseconds(150)); gestureMoved = false } }
        }
        .onChange(of: homeDrag.item) { _, value in if value != nil { actionEdge = 0; dragOffset = 0; gestureMoved = true } }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: actionEdge)
    }

    private var deleteButton: some View {
        Button { remove(); actionEdge = 0 } label: {
            Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 64, height: 72)
        }.buttonStyle(.plain).accessibilityLabel("Delete").accessibilityHidden(!revealed).opacity(revealed ? 1 : 0)
    }

    private var row: some View {
        HStack(spacing: 0) {
            Button { if !gestureMoved && homeDrag.item == nil { if actionEdge == 0 { toggle() } else { actionEdge = 0 } } } label: { label }
                .buttonStyle(.plain).accessibilityLabel(completionLabel).accessibilityValue(subtitle).accessibilityIdentifier("checklist-title")
            if !moves.isEmpty {
                Menu { ForEach(moves, id: \.title) { Button($0.title, action: $0.action) } } label: {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).frame(width: 34, height: 54).contentShape(Rectangle())
                }.accessibilityLabel("Move " + title)
            }
            Button { if !gestureMoved { edit() } } label: {
                Image(systemName: "pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 38, height: 54).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Edit " + title)
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 23, weight: .regular)).foregroundStyle(done ? color : color.opacity(0.65))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(done ? .secondary : .primary).strikethrough(done).fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }.padding(.leading, 14).padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).contentShape(Rectangle())
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 10)
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
    @State private var error: String?
    @State private var feedback = 0
    private var checked: Bool { PlannerLogic.checkedToday(habit, logs: logs, at: date) }
    var body: some View {
        CheckTile(title: habit.title, subtitle: PlannerLogic.detail(habit, logs: logs, at: date), done: checked, color: DayTheme.color(habit.color),
                  completionLabel: (checked ? "Undo " : "Log ") + habit.title,
                  toggle: toggle, edit: { edit?() }, remove: { change { try Conversions.remove(habit, in: context) } })
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
