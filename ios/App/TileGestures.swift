import SwiftUI
import SwiftData
import UIKit

// Rows swipe sideways: left a little reveals Delete, left all the way deletes, and right edits.
// Only sideways movement belongs to the row; vertical movement belongs to the scroll view.
// Touch and hold opens the standard context menu for everything else.

/// A pan that refuses to begin unless the finger is moving mostly sideways.
@available(iOS 18.0, *)
struct SidewaysPan: UIGestureRecognizerRepresentable {
    var changed: (CGFloat) -> Void
    /// The distance moved and the speed at release, in points a second.
    var ended: (CGFloat, CGFloat) -> Void
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }
    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let x = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed: changed(x)
        case .ended: ended(x, pan.velocity(in: pan.view).x)
        // An interrupted swipe (a call, an alert) settles back rather than acting.
        case .cancelled, .failed: ended(0, 0)
        default: break
        }
    }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }
    }
}

/// What a swiped row tells its content, so a tap that belongs to the swipe never also acts on the row.
struct SwipeRowState {
    /// The row is being swiped, or was a moment ago.
    let moved: Bool
    /// Delete is showing.
    let open: Bool
    let close: () -> Void
    /// Call first in the row's own tap actions. True means the tap was used up: a touch that ends a
    /// swipe does nothing, and a tap while Delete is showing closes it.
    func takesTap() -> Bool {
        if moved { return true }
        if open { close(); return true }
        return false
    }
}

extension Notification.Name {
    /// A row began to swipe; any other row showing Delete closes. The object is the swiping row's id.
    static let orbitRowSwipeBegan = Notification.Name("OrbitRowSwipeBegan")
}

/// A row that swipes like Mail and Reminders. Left a little reveals Delete; left past halfway (or a
/// quick flick) deletes in one motion. Right pulls out Edit, which opens when released past its mark.
/// The row follows the finger, there is a light tap at each commit point, and it settles with a spring.
struct SwipeRow<Content: View>: View {
    var radius: CGFloat = 0
    /// Swipe right; nil leaves the row with the left swipe only.
    var edit: (() -> Void)? = nil
    var editSymbol = "pencil"
    var deleteLabel = "Delete"
    var remove: () -> Void
    @ViewBuilder var content: (SwipeRowState) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.orbitAccent) private var accent
    @State private var id = UUID()
    /// Where the row sits: negative to the left (Delete), positive to the right (Edit).
    @State private var offset: CGFloat = 0
    /// Delete is showing and waits for a tap.
    @State private var open = false
    /// -1: letting go now deletes. 1: letting go now edits.
    @State private var armed = 0
    @State private var moved = false
    /// A finger is on the row and moving it.
    @State private var dragging = false
    @State private var width: CGFloat = 320
    @State private var bump = 0
    @GestureState private var legacyActive = false

    private let reveal: CGFloat = 76
    private let editMark: CGFloat = 68
    private var deleteMark: CGFloat { max(150, width * 0.55) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            actions
            content(SwipeRowState(moved: moved, open: open, close: { settle(open: false) }))
                .offset(x: offset)
        }
        .clipShape(shape)
        .contentShape(Rectangle())
        .background { GeometryReader { proxy in
            Color.clear.onAppear { width = proxy.size.width }.onChange(of: proxy.size.width) { _, value in width = value }
        } }
        .modifier(SidewaysDrag(changed: changed, ended: ended, legacy: legacy))
        // A swipe that was interrupted rather than let go settles back.
        .onChange(of: legacyActive) { _, active in if !active && dragging { ended(0, 0) } }
        .onReceive(NotificationCenter.default.publisher(for: .orbitRowSwipeBegan)) { note in
            if open, (note.object as? UUID) != id { settle(open: false) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: bump)
    }

    /// What shows behind the row: red with a bin on the right, the accent with a pencil on the left.
    @ViewBuilder private var actions: some View {
        if offset < 0 {
            Color.red.overlay(alignment: .trailing) {
                Button(action: delete) {
                    Image(systemName: "trash").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .scaleEffect(armed == -1 ? 1.25 : 1)
                        .animation(reduceMotion ? nil : .orbitLift, value: armed)
                        .frame(width: reveal).frame(maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(deleteLabel).accessibilityHidden(!open)
            }
        } else if offset > 0 {
            accent.fill.overlay(alignment: .leading) {
                Image(systemName: editSymbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .scaleEffect(armed == 1 ? 1.25 : 1)
                    .animation(reduceMotion ? nil : .orbitLift, value: armed)
                    .frame(width: editMark).accessibilityHidden(true)
            }
        }
    }

    private func changed(_ x: CGFloat) {
        if !dragging {
            dragging = true; moved = true
            NotificationCenter.default.post(name: .orbitRowSwipeBegan, object: id)
        }
        var value = (open ? -reveal : 0) + x
        let limit = editMark + 12
        if value > 0 {
            // Edit pulls out to its mark, then resists.
            if edit == nil { value = 0 }
            else if value > limit { value = limit + (value - limit) * 0.2 }
        } else {
            value = max(value, -width)
        }
        offset = value
        var next = 0
        if value <= -deleteMark { next = -1 }
        else if edit != nil && value >= editMark { next = 1 }
        if next != armed {
            if next != 0 { bump += 1 }
            armed = next
        }
    }

    private func ended(_ x: CGFloat, _ velocity: CGFloat) {
        guard dragging || open else { return }
        dragging = false
        let value = (open ? -reveal : 0) + x
        // A quick flick counts where it would have come to rest, once it is clearly past Delete.
        let flick = value < -reveal * 1.4 && value + velocity * 0.12 <= -deleteMark
        if value <= -deleteMark || flick {
            if armed != -1 { bump += 1 }
            delete()
        } else if let edit, value >= editMark {
            settle(open: false)
            edit()
        } else {
            // A short swipe, or one let go while heading back, closes; otherwise Delete stays showing.
            settle(open: value < 0 && velocity < 300 && (value < -reveal / 2 || velocity < -500))
        }
        armed = 0
        Task { try? await Task.sleep(for: .milliseconds(180)); moved = false }
    }

    /// Carries on off the edge, then removes the item. If it could not be removed, the row comes back.
    private func delete() {
        armed = 0; dragging = false
        if reduceMotion {
            remove()
        } else {
            withAnimation(.easeOut(duration: 0.16)) { offset = -width } completion: { remove() }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if offset != 0 { settle(open: false) }
        }
    }

    private func settle(open now: Bool) {
        withAnimation(reduceMotion ? nil : .orbitFold) {
            open = now
            offset = now ? -reveal : 0
        }
    }

    /// iOS 17 only; iOS 18 and later use `SidewaysPan`, which leaves vertical drags to the scroll view.
    private var legacy: some Gesture {
        // Starts later than the page's own scrolling (about 10 pt), so vertical movement scrolls
        // and only a clearly sideways swipe moves the row.
        DragGesture(minimumDistance: 24)
            .updating($legacyActive) { _, active, _ in active = true }
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) * 1.4 { changed(value.translation.width) }
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { ended(0, 0); return }
                ended(value.translation.width, value.velocity.width)
            }
    }
}

/// The sideways swipe: a UIKit pan on iOS 18 and later, the SwiftUI gesture on iOS 17.
private struct SidewaysDrag<Legacy: Gesture>: ViewModifier {
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat) -> Void
    var legacy: Legacy
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.gesture(SidewaysPan(changed: changed, ended: ended)) }
        else { content.simultaneousGesture(legacy) }
    }
}

/// Checking something off shows at once, then waits a moment before the list changes, so the tick is
/// seen landing and the row folds away instead of vanishing under the finger. Ticking several in a
/// row keeps them all in place until there is a pause; tapping one again inside that pause takes the
/// tick back and nothing is saved.
@MainActor final class CompletionHold {
    static let shared = CompletionHold()
    /// How long a ticked row stays where it is.
    static let pause: Duration = .milliseconds(380)
    private var waiting: [(key: String, commit: () -> Void)] = []
    private var timer: Task<Void, Never>?

    /// Saves `commit` after the pause; a later tick starts the pause again for all of them.
    func schedule(_ key: String, commit: @escaping () -> Void) {
        waiting.removeAll { $0.key == key }
        waiting.append((key, commit))
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// The tick was taken back before it was saved.
    func cancel(_ key: String) {
        waiting.removeAll { $0.key == key }
        if waiting.isEmpty { timer?.cancel(); timer = nil }
    }

    /// Saves everything that is waiting now: when the pause ends, or as Orbit leaves the screen.
    func flush(animated: Bool = true) {
        timer?.cancel(); timer = nil
        let work = waiting
        waiting = []
        guard !work.isEmpty else { return }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            withAnimation(.orbitFold) { for item in work { item.commit() } }
        } else {
            for item in work { item.commit() }
        }
    }
}

/// Reminders are rebuilt after quick edits such as ticks, but only once things have settled, so the
/// work never competes with an animation and several ticks in a row rebuild them once.
@MainActor enum ReminderRefresh {
    private static var waiting: Task<Void, Never>?
    static func soon(_ context: ModelContext) {
        waiting?.cancel()
        waiting = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            try? await refreshReminders(context)
        }
    }
}
